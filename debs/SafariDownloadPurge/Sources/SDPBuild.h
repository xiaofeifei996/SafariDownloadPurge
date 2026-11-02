#pragma once

// Build identifier compiled into the dylib. The panel compares it against the
// value the running Safari process reports, which reveals when Safari is still
// serving an older image and a restart is needed.
#define SDP_BUILD_STAMP @"1.1.7"
