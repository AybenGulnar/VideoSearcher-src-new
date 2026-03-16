#!/bin/bash
# Install Apache JMeter on an EC2 instance (Amazon Linux 2023 or Ubuntu)
set -e

JMETER_VERSION="5.6.3"
JMETER_DIR="$HOME/apache-jmeter-${JMETER_VERSION}"

# Try Amazon Linux 2023 (dnf) first, then fall back to Ubuntu/Debian (apt-get)
sudo dnf install -y java-17-amazon-corretto-headless 2>/dev/null \
  || sudo apt-get install -y openjdk-17-jre-headless 2>/dev/null \
  || { echo "Java installation failed, check my distro"; exit 1; }

# Skip download if JMeter is already installed at the expected path
if [ -d "$JMETER_DIR" ]; then
  echo "JMeter already installed: $JMETER_DIR"
else
  echo "Downloading JMeter ${JMETER_VERSION}"
  cd "$HOME"
  wget -q "https://downloads.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"
  tar xzf "apache-jmeter-${JMETER_VERSION}.tgz"
  # Remove the archive after extraction to save disk space
  rm "apache-jmeter-${JMETER_VERSION}.tgz"
  echo "JMeter installed: $JMETER_DIR"
fi

echo ""
echo "Finished."
