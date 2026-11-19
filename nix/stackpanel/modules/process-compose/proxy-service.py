"""Open this service's project-local identity on fd 9, then replace the launcher."""

import os
import stat
import sys


def open_identity(module, service):
    # process-compose starts service commands in the project root. Never use
    # a path supplied by the service environment to select another project.
    root = os.environ.get("STACKPANEL_ROOT")
    if root and not os.path.samefile(".", root):
        raise ValueError("proxy service must start in the project root")

    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    directory = os.open(".", directory_flags)
    try:
        for component in (".stack", "state", "proxy", module):
            try:
                os.mkdir(component, 0o700, dir_fd=directory)
            except FileExistsError:
                pass
            child = os.open(component, directory_flags, dir_fd=directory)
            os.close(directory)
            directory = child
            info = os.fstat(directory)
            if info.st_uid != os.geteuid() or info.st_mode & 0o022:
                raise ValueError("unsafe proxy identity directory: " + component)

        # O_NONBLOCK prevents a preexisting FIFO from hanging the launcher.
        fd = os.open(service + ".identity", os.O_RDONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK,
                     0o600, dir_fd=directory)
        info = os.fstat(fd)
        if not (stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600
                and info.st_uid == os.geteuid() and info.st_nlink == 1):
            os.close(fd)
            raise ValueError("unsafe proxy identity file")
        return fd
    finally:
        os.close(directory)


if __name__ == "__main__":
    module, service, executable, *args = sys.argv[1:]
    # The Nix caller validates these are individual URI-unreserved components.
    # Defend that filesystem boundary here too before passing either to openat.
    if any(part in ("", ".", "..") or "/" in part for part in (module, service)):
        sys.exit("invalid proxy identity path component")
    mask = os.umask(0o077)
    try:
        fd = open_identity(module, service)
        if fd != 9:
            os.dup2(fd, 9, inheritable=True)
            os.close(fd)
        else:
            os.set_inheritable(9, True)
    finally:
        os.umask(mask)
    os.execv(executable, [executable, *args])
