# Changelog

All notable changes to the EMP MGPU project will be documented in this file.

## [Unreleased]

### Added
- [2025-04-07 16:17] Added worker auto-restart mechanism with configurable retry limits and delays
- [2025-04-07 16:17] Added worker_watchdog.sh script to monitor worker processes and restart them if they crash
- [2025-04-07 16:18] Added init.d compatible script for the worker watchdog (Docker-friendly)
- [2025-04-07 16:24] Updated Dockerfile to include worker watchdog scripts and set them to start automatically

### Changed
- [2025-04-07 16:00] Updated worker script to check for worker_main.py as the primary entry point and fall back to worker.py if needed
- [2025-04-07 16:00] Updated process detection in worker script to also look for worker_main.py processes
