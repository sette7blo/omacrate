"""Reads the picture picked for a playlist's artwork, for bin/omacrate.

The picker hands over a path. A path in a folder another account can change
could already name a different file when it is opened, so such a path is
refused: every folder on the way to the file, and the file itself, must be
changeable by no other account. A folder others may write to is accepted only
when it is sticky (like /tmp) and the entry in it belongs to this account or
root, because nobody else can then rename or replace that entry.

The real path is walked one component at a time, each opened without
following a link, so a folder swapped for a link during the walk makes it
fail rather than lead somewhere else. The folder holding the picked path is
checked too, in case the picked name itself is a link. The regular-file check
and the bounded read are made on the one open file.

Prints the file (at most 10 MB plus one byte, so the caller can tell it is
too big) on stdout. Exit codes: 2 cannot be opened, 3 not a regular file,
4 in a folder another account can change, 5 the file itself can be changed
by another account.
"""

import os
import stat
import sys

LIMIT = 10 * 1024 * 1024 + 1
UID = os.getuid()
GID = os.getgid()


class Unsafe(Exception):
    """A folder on the way that another account can change."""


def owned_safely(st):
    return st.st_uid in (UID, 0)


def unchangeable_by_others(st):
    """No other account can write to it: owned by us or root, not
    world-writable, and group-writable only for our own primary group."""
    if not owned_safely(st):
        return False
    if st.st_mode & stat.S_IWOTH:
        return False
    if st.st_mode & stat.S_IWGRP and st.st_gid != GID:
        return False
    return True


def folder_keeps(parent, child):
    """Nobody else can rename, remove or replace the child entry."""
    if unchangeable_by_others(parent):
        return True
    # A sticky folder (like /tmp): only an entry's owner (or the folder's)
    # can rename or remove it.
    return bool(parent.st_mode & stat.S_ISVTX) and owned_safely(parent) and owned_safely(child)


def walk(path, last_flags):
    """Opens path component by component without following links; checks
    each folder against the entry opened in it. Returns the last fd."""
    parts = [p for p in path.split("/") if p]
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for i, part in enumerate(parts):
            last = i == len(parts) - 1
            flags = (last_flags if last else os.O_RDONLY | os.O_DIRECTORY) | os.O_NOFOLLOW | os.O_CLOEXEC
            child = os.open(part, flags, dir_fd=fd)
            if not folder_keeps(os.fstat(fd), os.fstat(child)):
                os.close(child)
                raise Unsafe(part)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def main():
    if len(sys.argv) != 2 or not sys.argv[1].startswith("/"):
        return 2
    picked = sys.argv[1]
    try:
        # The folder the picked name is in, then the file it leads to.
        os.close(walk(os.path.realpath(os.path.dirname(picked)), os.O_RDONLY | os.O_DIRECTORY))
        fd = walk(os.path.realpath(picked), os.O_RDONLY | os.O_NONBLOCK)
    except Unsafe:
        return 4
    except OSError:
        return 2
    # Checked on the open handle itself, before anything reads from it.
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):
        os.close(fd)
        return 3
    if not unchangeable_by_others(st):
        os.close(fd)
        return 5
    with os.fdopen(fd, "rb") as f:
        sys.stdout.buffer.write(f.read(LIMIT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
