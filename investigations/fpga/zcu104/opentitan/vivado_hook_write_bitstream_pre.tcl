# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Bypass this for now for the ZCU104 board.
#
# set workroot [file dirname [info script]]

# send_msg "Designcheck 1-1" INFO "Checking design"

# Ensure the design meets timing
# set slack_ns [get_property SLACK [get_timing_paths -delay_type min_max]]
# send_msg "Designcheck 1-2" INFO "Slack is ${slack_ns} ns."

# if [expr {$slack_ns < 0}] {
#  send_msg "Designcheck 1-3" INFO "Timing failed. Slack is ${slack_ns} ns."
# }

