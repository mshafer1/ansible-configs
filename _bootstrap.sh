# bail if we hit an error
set -e

# update indexes
apt-get update

# install Python3 and pip3
apt-get install python3 python3-pip

# Use pip to install ansible
pip3 install --user ansible
