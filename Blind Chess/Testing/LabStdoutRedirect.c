//
//  LabStdoutRedirect.c
//  Blind Chess
//
//  Test-lab hook (Tools/AppLab). When the app is launched with the environment
//  variable BLINDCHESS_LOG_FILE=<absolute path> (the XCUITests set it), stdout and
//  stderr are appended to that file so the app's print() output can be collected
//  from simulator runs. Without the variable this does nothing.
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
    if (freopen(path, "a", stderr) != NULL) {
        setvbuf(stderr, NULL, _IONBF, 0);
    }
}
