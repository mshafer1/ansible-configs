#!/bin/sh
set -eu

# Initialize our own variables
stream_id=""
stream_source=""
api_key=""
debug=0

while [ $# -gt 0 ]; do
  case $1 in
    -id|--stream-id)
      stream_id="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--stream-source)
      stream_source="$2"
      shift # past argument
      shift # past value
      ;;
    --api-key)
      api_key="$2"
      shift # past argument
      shift # past value
      ;;
    -v)
      debug=1
      shift
      ;;
    -*|*)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

print_help() {
    echo "Usage: $0 [-id/--stream-id id_field] [-s/--stream-source] --api-key API_KEY" >&2
    echo "If id is passed, the info for that stream is looked up." >&2
    echo "If stream-source is passed, it must be a redirect to a youtube url with a steam id to check" >&2
}

debug_print() {
if [ $debug -eq 1 ]; then
    echo -e "$1"
fi
}

if [ -z "$api_key" ]; then
    print_help
    echo "" >&2
    echo "--api-key must be passed" >&2
    exit 1
fi

if [ -z "$stream_id" ]; then
    if [ -z "$stream_source" ]; then
        echo "Error, either --stream-source or --stream-id must be passed." >&2
        print_help
        exit 1
    fi

    stream_link=$(curl -Ls -o /dev/null -w %{url_effective} "$stream_source")
    debug_print "Stream link is $stream_link"
    query_string=$(echo "$stream_link" | sed -e 's/^.*?//g')
    debug_print "Query string is $query_string"

    # Extract the value of the 'q' parameter
    stream_id=$(echo "$query_string" | sed -n 's/.*v=\([^&]*\).*/\1/p')
    echo "Stream ID is $stream_id"
fi

actual_start_time=$(curl -s "https://www.googleapis.com/youtube/v3/videos?key=${api_key}&part=liveStreamingDetails&id=${stream_id}" | jq '.items[0].liveStreamingDetails.actualStartTime')
echo ""
echo "Actual start time: $actual_start_time"

if [ "$actual_start_time" = "null" ]; then
    echo "" >&2
    echo "Trouble getting the stream live?" >&2
    echo "Stream ${stream_id} is not started yet." >&2
    echo "" >&2
    echo "Text Matthew if you need help." >&2
    exit 2
fi