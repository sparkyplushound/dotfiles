# time_rz.m4
# serial 1
dnl Copyright (C) 2015-2025 Free Software Foundation, Inc.
dnl This file is free software; the Free Software Foundation
dnl gives unlimited permission to copy and/or distribute it,
dnl with or without modifications, as long as this notice is preserved.

dnl Time zone functions: tzalloc, localtime_rz, etc.

dnl Written by Paul Eggert.

AC_DEFUN([gl_TIME_RZ],
[
  AC_REQUIRE([gl_USE_SYSTEM_EXTENSIONS])
  AC_REQUIRE([gl_TIME_H_DEFAULTS])
  AC_REQUIRE([AC_STRUCT_TIMEZONE])

  # On Mac OS X 10.6, localtime loops forever with some time_t values.
  # See Bug#27706, Bug#27736, and
  # https://lists.gnu.org/r/bug-gnulib/2017-07/msg00142.html
  AC_CACHE_CHECK([whether localtime works even near extrema],
    [gl_cv_func_localtime_works],
    [gl_cv_func_localtime_works=yes
     AC_RUN_IFELSE(
       [AC_LANG_PROGRAM(
          [[#include <stdlib.h>
            #include <string.h>
            #include <unistd.h>
            #include <time.h>
          ]], [[
            time_t t = -67768038400666600;
            struct tm *tm;
            char *tz = getenv ("TZ");
            if (! (tz && strcmp (tz, "QQQ0") == 0))
              return 0;
            alarm (2);
            tm = localtime (&t);
            /* Use TM and *TM to suppress over-optimization.  */
            return tm && tm->tm_isdst;
          ]])],
       [(TZ=QQQ0 ./conftest$EXEEXT) >/dev/null 2>&1 ||
           gl_cv_func_localtime_works=no],
       [],
       [gl_cv_func_localtime_works="guessing yes"])])
  if test "$gl_cv_func_localtime_works" = no; then
      AC_DEFINE([HAVE_LOCALTIME_INFLOOP_BUG], 1,
        [Define if localtime-like functions can loop forever on
         extreme arguments.])
  fi

  AC_CHECK_TYPES([timezone_t], [], [], [[#include <time.h>]])
  if test "$ac_cv_type_timezone_t" = yes; then
    HAVE_TIMEZONE_T=1
  fi
])
