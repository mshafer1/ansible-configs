# bail if we hit an error
set -e

# update indexes
apt-get update

# install Python3 and pip3
apt-get install python3 python3-pip

# Use pip to install ansible
pip3 install --user ansible

# If pip binary path is not on the PATH var, add it to profile file
echo $PATH | grep "\.local" > /dev/null || echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc


# If pip binary path is not on the PATH var, add it PATH for this session
echo $PATH | grep "\.local" > /dev/null || export PATH=$PATH:~/.local/bin

