/* testmini.c -- very simple test program for the miniLZO library

   This file is part of the LZO real-time data compression library.

   Copyright (C) 1996-2017 Markus Franz Xaver Johannes Oberhumer
   All Rights Reserved.

   The LZO library is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of
   the License, or (at your option) any later version.

   The LZO library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with the LZO library; see the file COPYING.
   If not, write to the Free Software Foundation, Inc.,
   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

   Markus F.X.J. Oberhumer
   <markus@oberhumer.com>
   http://www.oberhumer.com/opensource/lzo/
 */


#include <stdio.h>
#include <stdlib.h>


/*************************************************************************
// This program shows the basic usage of the LZO library.
// We will compress a block of data and decompress again.
//
// For more information, documentation, example programs and other support
// files (like Makefiles and build scripts) please download the full LZO
// package from
//    http://www.oberhumer.com/opensource/lzo/
**************************************************************************/

/* First let's include "minlzo.h". */

#include "minilzo.h"


static unsigned char __LZO_MMODEL *in  = NULL;
static unsigned char __LZO_MMODEL *out = NULL;


/* Work-memory needed for compression. Allocate memory in units
 * of 'lzo_align_t' (instead of 'char') to make sure it is properly aligned.
 */

#define HEAP_ALLOC(var,size) \
    lzo_align_t __LZO_MMODEL var [ ((size) + (sizeof(lzo_align_t) - 1)) / sizeof(lzo_align_t) ]

static HEAP_ALLOC(wrkmem, LZO1X_1_MEM_COMPRESS);


/*************************************************************************
//
**************************************************************************/

int main(int argc, char *argv[])
{
    FILE *inf = NULL, *outf = NULL;

    int r;
    int result = 0;
    lzo_uint in_len;
    lzo_uint out_len;

    if (argc != 3) {
        printf("Usage: %s <in> <out>\n", argv[0]);
        return 0;
    }

/*
 * Step 1: initialize the LZO library
 */
    if (lzo_init() != LZO_E_OK)
    {
        printf("internal error - lzo_init() failed !!!\n");
        printf("(this usually indicates a compiler bug - try recompiling\nwithout optimizations, and enable '-DLZO_DEBUG' for diagnostics)\n");
        return 3;
    }

/*
 * Step 2: prepare the input block that will get compressed.
 *         We just fill it with zeros in this example program,
 *         but you would use your real-world data here.
 */
    inf = fopen(argv[1], "r");
    if (inf == NULL) {
        printf("Can't open file for reading: %s\n", argv[1]);
        return 1;
    }

    fseek(inf, 0, SEEK_END);
    in_len = ftell(inf);
    out_len = in_len + in_len / 16 + 64 + 3;
    rewind(inf);

    in = malloc(in_len);
    out = malloc(out_len);

    if (in == NULL || out == NULL) {
        printf("Memory allocation error\n");
        result = 1;
        goto out;
    }

    if (fread (in, in_len, 1, inf) != 1) {
        printf("File read error\n");
        result = 1;
        goto out;
    }

/*
 * Step 3: compress from 'in' to 'out' with LZO1X-1
 */
    outf = fopen(argv[2], "w");
    if (outf == NULL) {
        printf("Can't open file for writing: %s\n", argv[2]);
        return 1;
    }

    r = lzo1x_1_compress(in,in_len,out,&out_len,wrkmem);
    if (r != LZO_E_OK) {
        /* this should NEVER happen */
        printf("internal error - compression failed: %d\n", r);
        result = 2;
        goto out;
    }

    if (fwrite(out, out_len, 1, outf) != 1) {
        printf("File write error\n");
        result = 1;
        goto out;
    }

out:
    if (outf) fclose(outf);
    if (inf) fclose(inf);
    free(out);
    free(in);
    return result;
}


/* vim:set ts=4 sw=4 et: */
