#!/bin/bash

# download the latest stage3 tarball

KIND=amd64-systemd && URL_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-${KIND}" && TARBALL=$(curl -s "${URL_BASE}/latest-stage3-${KIND}.txt" | grep -o "stage3-${KIND}-[^ ]*\.tar\.xz") && curl -O "${URL_BASE}/${TARBALL}" && curl -s "${URL_BASE}/${TARBALL}.sha256" | grep -oP '^[a-f0-9]{64}' | sed "s|$|  ${TARBALL}|" | sha256sum -c
