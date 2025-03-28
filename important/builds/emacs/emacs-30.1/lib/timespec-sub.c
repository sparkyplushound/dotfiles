/* Subtract two struct timespec values.

   Copyright (C) 2011-2025 Free Software Foundation, Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* Written by Paul Eggert.  */

/* Return the difference between two timespec values A and B.  On
   overflow, return an extremal value.  This assumes 0 <= tv_nsec <
   TIMESPEC_HZ.  */

#include <config.h>
#include "timespec.h"

#include <stdckdint.h>
#include "intprops.h"

struct timespec
timespec_sub (struct timespec a, struct timespec b)
{
  time_t rs = a.tv_sec;
  time_t bs = b.tv_sec;
  int ns = a.tv_nsec - b.tv_nsec;
  int rns = ns;

  if (ns < 0)
    {
      rns = ns + TIMESPEC_HZ;
      time_t bs1;
      if (!ckd_add (&bs1, bs, 1))
        bs = bs1;
      else if (- TYPE_SIGNED (time_t) < rs)
        rs--;
      else
        goto low_overflow;
    }

  if (ckd_sub (&rs, rs, bs))
    {
      if (0 < bs)
        {
        low_overflow:
          rs = TYPE_MINIMUM (time_t);
          rns = 0;
        }
      else
        {
          rs = TYPE_MAXIMUM (time_t);
          rns = TIMESPEC_HZ - 1;
        }
    }

  return make_timespec (rs, rns);
}
