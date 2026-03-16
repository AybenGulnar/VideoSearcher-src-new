#!/bin/bash
# Install Locust and its dependencies on an EC2 instance (Amazon Linux 2023 or Ubuntu)
set -e

# Try Amazon Linux 2023 (dnf) first, then fall back to Ubuntu/Debian (apt-get)
sudo dnf install -y python3 python3-pip 2>/dev/null \
  || sudo apt-get install -y python3 python3-pip 2>/dev/null \
  || { echo "Python3 failed"; exit 1; }

echo ""
echo "Installing"
# numpy and pandas are required by locustfile.py for the workload profile;
# matplotlib is needed by plot_results.py to generate the HTML report charts
pip3 install --quiet locust numpy pandas matplotlib

echo ""
echo "Finished."
