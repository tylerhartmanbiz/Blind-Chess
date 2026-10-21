//
//  LabStdoutRedirect.c
//  Blind Chess
//
//  Test-lab hook (Tools/AppLab). When the app is launched with the environment
//  variable BLINDCHESS_LOG_FILE=<absolute path> (the XCUITests set it; for
//  `simctl launch` use SIMCTL_CHILD_BLINDCHESS_LOG_FILE), stdout is appended to that
//  file, line-buffered, so the app's print() output can be collected from simulator
//  runs. stderr is left alone (under XCTest it carries noisy os_log mirroring).
//  Without the variable this does nothing.
//

#include <stdio.h>
#include <stdlib.h>

__attribute__((constructor))
static void blindchess_lab_redirect_stdout(void) {
    const char *path = getenv("BLINDCHESS_LOG_FILE");
    if (path == NULL || path[0] == '\0') {
        return;
    }
    if (freopen(path, "a", stdout) != NULL) {
        setvbuf(stdout, NULL, _IOLBF, 0);
    }
}
