#!/bin/bash
set -e
set -x

pub get
pub run test
