# Test Commands

---

## 0. Upload Test Video (run once before testing)

The test video is `video_cut.mp4`. Upload it to the S3 input bucket before running any load test:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 cp video_cut.mp4 s3://videosearcher-input-new-${ACCOUNT_ID}/video_cut.mp4
```

> Both JMeter and Locust tests are configured to use `video_cut.mp4` as the input file.

---

## 1. SSH Access (run once per session)

```bash
MY_IP=$(curl -s https://api4.ipify.org)
aws ec2 authorize-security-group-ingress \
  --group-id <your-security-group-id> \
  --protocol tcp \
  --port 22 \
  --cidr ${MY_IP}/32
```

---

## 2. Locust — EC2

```bash
cd VideoSearcher-src/locust-tests

./run-locust-on-ec2.sh \
  -k ~/.ssh/videosearcher-jmeter-key.pem \
  -h <ec2-public-ip>
```

---

## 3. JMeter — EC2

```bash
cd VideoSearcher-src/jmeter-tests

./run-test-on-ec2.sh \
  -k ~/.ssh/videosearcher-jmeter-key.pem \
  -h <ec2-public-ip> \
  -p 60
```

---

## 4. JMeter — Local (videosearcher-http-test.jmx)

```bash
cd VideoSearcher-src

jmeter -n \
  -t jmeter-tests/videosearcher-http-test.jmx \
  -l results/local-$(date +%H%M%S)-raw.jtl \
  -e -o results/local-$(date +%H%M%S)-report \
  -Jphaseduration=60
```

---

## 5. JMeter — Local (videosearcher-simple-5users.jmx)

```bash
cd VideoSearcher-src

jmeter -n \
  -t jmeter-tests/videosearcher-simple-5users.jmx \
  -l results/simple-$(date +%H%M%S)-raw.jtl \
  -e -o results/simple-$(date +%H%M%S)-report \
  -Jduration=60 \
  -Jthinktime=5000
```
