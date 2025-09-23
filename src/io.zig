const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const linux = os.linux;
const IoUring = linux.IoUring;
const Allocator = std.mem.Allocator;

const linux_version = "5.1.0";
const io_entries = 32;
const flags = 0;

const IoError = error{
    UnsupportedPlatform,
    InvalidLinuxVer
};

// Setups uo io_uring interface
pub fn setup_io(alloc: *Allocator) !IoUring {
    // Platform Check
    switch (builtin.os.tag) {
        .linux => {
            const version_range = builtin.os.versionRange();
            switch (version_range) {
                .linux => |l| {
                    const sem_ver = try std.SemanticVersion.parse(linux_version);
                    const in_range = try l.isAtLeast(sem_ver);
                    if (!in_range) {
                        return IoError.InvalidLinuxVer;
                    }
                },
                else => return IoError.UnsupportedPlatform
            }
        },
        else => return IoError.UnsupportedPlatform
    }

    return try IoUring.init(io_entries, flags);
}

pub fn accept_io(io: IoUring) {
    io.accept(user_data: u64, fd: either type, addr: ?*either type, addrlen: ?*u32, flags: u32)
}
