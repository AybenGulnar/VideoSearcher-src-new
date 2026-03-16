import json
import numpy as np
import time
import random
from locust import HttpUser, task, between, events
import gevent
from gevent import sleep
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime

# Target API endpoint configuration
HOST          = "YOUR-API-ID.execute-api.YOUR-REGION.amazonaws.com"
API_PATH      = "/prod/process"
VIDEO         = "video_cut.mp4"

# workloadProfile.csv contains a per-second RPS column that defines the
# arrival rate trace; the test replays this trace via a Poisson process
WORKLOAD_CSV  = "workloadProfile.csv"

df_profile = pd.read_csv(WORKLOAD_CSV, sep=';')
rps_pattern = df_profile['RPS'].values
SECONDS = len(rps_pattern)

print(f"Loaded workload profile: {SECONDS}s, max RPS={np.max(rps_pattern):.4f}, mean RPS={np.mean(rps_pattern):.4f}")

# In-memory log of every request; flushed to request_timestamps.csv at test end
request_timestamps = []

def log_request(timestamp, response_time, status_code):
    request_timestamps.append((timestamp, response_time, status_code))

def save_request_log():
    timestamps_df = pd.DataFrame(request_timestamps, columns=['Timestamp', 'ResponseTime', 'StatusCode'])
    timestamps_df.to_csv('request_timestamps.csv', index=False)
    print(f"Saved {len(request_timestamps)} request records to request_timestamps.csv")

# Flush the request log when the test finishes so no data is lost
@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    save_request_log()


class VideoSearcherUser(HttpUser):
    # wait_time is set to zero because request timing is controlled entirely
    # by the trace-driven scheduler inside trace_loop
    wait_time = between(0, 0)
    host = f"https://{HOST}"

    def on_start(self):
        pass

    @task
    def post_task(self):
        pass  # run loop is overridden below

    def run(self):
        self.trace_loop()

    def trace_loop(self):
        # Pre-compute every request's absolute send time for the full test duration
        all_request_times = self.generate_nonhomogeneous_poisson_times()

        print(f"Generated {len(all_request_times)} total requests over {SECONDS}s")

        if len(all_request_times) > 0:
            self.analyze_request_distribution(all_request_times)

        # Schedule each request as a non-blocking greenlet; gevent fires them at
        # the correct wall-clock offset relative to test start
        for request_time in all_request_times:
            if request_time < SECONDS:
                gevent.spawn_later(request_time, self.make_request)

        # Block this greenlet for the full trace duration so the process stays alive
        sleep(SECONDS)

        save_request_log()
        self.environment.runner.quit()

    def generate_nonhomogeneous_poisson_times(self):
        """
        Lewis-Shedler thinning algorithm for a non-homogeneous Poisson process.

        Steps:
        1. Generate candidate arrival times from a homogeneous Poisson process
           at the maximum rate (upper bound).
        2. Accept each candidate at time t with probability rate(t) / max_rate.
        The resulting accepted times follow the original time-varying rate.
        """
        max_rps = np.max(rps_pattern)
        print(f"Max RPS: {max_rps:.4f} | Min: {np.min(rps_pattern):.4f} | Mean: {np.mean(rps_pattern):.4f}")

        if max_rps <= 0:
            return []

        # Over-sample by 2× to ensure enough candidates after thinning
        expected_events = max_rps * SECONDS
        num_candidates = int(expected_events * 2.0) + 100

        inter_arrivals = np.random.exponential(1.0 / max_rps, num_candidates)
        candidate_times = np.cumsum(inter_arrivals)
        candidate_times = candidate_times[candidate_times < SECONDS]
        print(f"Candidate events: {len(candidate_times)}")

        # Thinning step: keep the candidate only if a uniform draw falls below
        # the ratio of the local rate to the maximum rate
        accepted_times = []
        for t in candidate_times:
            time_index = min(int(t), len(rps_pattern) - 1)
            current_rate = rps_pattern[time_index]
            if np.random.random() < current_rate / max_rps:
                accepted_times.append(t)

        accepted_times = np.array(accepted_times)
        print(f"Accepted events after thinning: {len(accepted_times)}")

        if len(accepted_times) > 0:
            actual_rate = len(accepted_times) / SECONDS
            theoretical_rate = np.mean(rps_pattern)
            print(f"Actual avg rate: {actual_rate:.4f} | Theoretical: {theoretical_rate:.4f}")

        return accepted_times

    def analyze_request_distribution(self, request_times):
        # Print inter-arrival statistics and per-minute binned rates as a
        # sanity check that the generated trace matches the workload profile
        if len(request_times) > 1:
            sorted_times = np.sort(request_times)
            inter_arrivals = np.diff(sorted_times)
            print(f"\nInter-arrival times: min={np.min(inter_arrivals):.4f}s, mean={np.mean(inter_arrivals):.4f}s, max={np.max(inter_arrivals):.4f}s")

        for bin_size in [60]:
            num_bins = int(SECONDS / bin_size)
            bins = np.linspace(0, SECONDS, num_bins + 1)
            hist, _ = np.histogram(request_times, bins=bins)
            rates = hist / bin_size
            print(f"\nRequest rate per {bin_size}s bins (first 10):")
            for i, rate in enumerate(rates[:10]):
                s, e = i * bin_size, (i + 1) * bin_size
                expected = np.mean(rps_pattern[s:e])
                print(f"  [{s:4d}-{e:4d}s]: {rate:.4f} RPS (expected {expected:.4f})")

    def make_request(self):
        path = f"{API_PATH}?video={VIDEO}"
        timestamp = datetime.now().timestamp()
        with self.client.post(path, catch_response=True) as response:
            log_request(timestamp, response.elapsed.total_seconds() * 1000, response.status_code)
