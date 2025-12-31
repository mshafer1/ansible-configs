#!/bin/env python3
import concurrent.futures
import datetime
import os
import time
import typing
import shlex
import signal
import subprocess
import logging

_LOGGER = logging.getLogger(__name__)
_LOGGER.addHandler(logging.NullHandler())

_WORK_DIR = "/var/tmp/multistreamer"


def setup_work_dir():
    os.makedirs(_WORK_DIR, mode=0o777, exist_ok=True)


class Push(typing.NamedTuple):
    url: str
    bandwidth: typing.Optional[str] = None
    framerate: int = 30
    scale: typing.Optional[str] = None
    name: str = ''

    @property
    def command(self):
        scale_arg = (
            "copy"
            if self.scale in {None, -1, "-1", "-1:-1"}
            else (
                f"libx264 -vf scale={self.scale} -preset veryfast "
                f"-tune zerolatency -g {self.framerate * 2} "
                f"-keyint_min {self.framerate * 4} -sc_threshold 0"
            )
        )

        bitrate_arg = ("" if self.bandwidth in {None, ""} else f"-b:v {self.bandwidth}")

        return shlex.split(
            "ffmpeg -i rtmp://localhost/live -c:a copy "
            f"-c:v {scale_arg} -crf {self.framerate} {bitrate_arg} -f flv "
            "-probesize 32 -analyzeduration 0 -fflags nobuffer -rw_timeout 50000 "
            f"-nostdin -progress ./progress_{self.name} "
            "-stats_period 1 -reconnect 1 -reconnect_streamed 1 "
            f"{self.url}"
        )


{% set alphabet = "abcdefghijklmnopqrstuvwxyz" %}
_PUSHES = (
  {% for push in _multistream_fail_over__pushes %}
  Push('{{push.url}}', '{{ push.bandwidth | default("") }}', {{ push.framerate | default(30) }}, {% if 'scale' in push %}"{{ push.scale }}"{% else %}None{% endif %}, "{{ alphabet[loop.index0] }}"),
  {% endfor %}
)


def get_thread_progress_time(name):
    if not os.path.exists(name):
        return 0
    m_timestamp = os.path.getmtime(name)
    return datetime.datetime.fromtimestamp(m_timestamp)


class Send:
    def __init__(
        self, e: concurrent.futures.ThreadPoolExecutor, push: Push, progress_name: str
    ):
        self.executor = e
        self.push = push
        self._last_progress_time = None
        self.progress_name = progress_name
        self._age_counter = 0
        self._start_time = None
        self._thread = None
        self._log_file = None

    def start(self):
        if self._thread is not None:
            self.stop()

        self._log_file = open(f"_log_{self.progress_name}", "w")
        _LOGGER.debug("Running: %s", self.push.command)
        self._thread = subprocess.Popen(self.push.command, stdout=self._log_file, stderr=subprocess.STDOUT)
        self._start_time = time.time()

    def stop(self):
        if self._thread is None:
            return
        _LOGGER.info("Shutting down thread: %s-%s", self.progress_name, self._thread)
        self._thread.send_signal(signal.SIGTERM)
        self._thread.terminate()
        self._thread.kill()
        self._thread.wait()
        _LOGGER.info("Thread status: %s", self._thread.poll())
        self._log_file.close()
        self._log_file = None
        self._start_time = None
        self._thread = None

    @property
    def run_time(self):
        if not self._start_time:
            return 0

        return time.time() - self._start_time

    @property
    def is_running(self):
        if not self._thread:
            return False

        return_code = self._thread.poll() # None if running, else, int

        return return_code is None

    @property
    def is_alive(self):
        current_progress_time = get_thread_progress_time(self.progress_name)
        if current_progress_time == self._last_progress_time:
            self._age_counter += 1
        else:
            self._age_counter = 0
        # _LOGGER.debug(" (%s) old: %20s new: %20s", self.progress_name, self._last_progress_time, current_progress_time)
        # _LOGGER.debug(" count: %s", self._age_counter)

        self._last_progress_time = current_progress_time

        return self.is_running and self._age_counter < 15

    @property
    def is_stable(self):
        return self.is_alive and (self.run_time > 15)


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s %(name)s-%(funcName)s %(levelname)s - %(message)s", level=logging.DEBUG)
    setup_work_dir()
    os.chdir(_WORK_DIR)
    main_push, alt_push, *_ = _PUSHES
    main_alive_last_time = False
    with concurrent.futures.ThreadPoolExecutor() as executor:
        main = Send(executor, main_push, "progress_a")
        alt = Send(executor, alt_push, "progress_b")
        main.start()

        try:
            while True:  # until terminated
                main_is_alive = main.is_alive
                alt_is_alive = alt.is_alive

                _LOGGER.info("Main running: %s/%s, Alt running: %s/%s", main_is_alive, main.is_stable, alt_is_alive, alt.is_stable)

                if not main_is_alive:
                    if not alt.is_running:
                        _LOGGER.info("  starting Alt")
                        alt.start()
                    elif not alt.is_alive and not main_alive_last_time:
                        _LOGGER.info("  Restarting Alt")
                        alt.start()

                    # attempt to restart main
                    if main_alive_last_time:
                        _LOGGER.info("  starting Main")
                        main.start()
                    main_alive_last_time = False
                else:
                    main_alive_last_time = True
                    if alt_is_alive and main.is_stable:
                        _LOGGER.info("  stopping Alt")
                        alt.stop()

                time.sleep(1)
        except (KeyboardInterrupt, SystemExit):
            _LOGGER.warning("Exiting...")
            # for each, send terminate ??
            pass

