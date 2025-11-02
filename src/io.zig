const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const linux = os.linux;
const File = std.fs.File;
const IoUring = linux.IoUring;
const Allocator = std.mem.Allocator;

const linux_version = "5.1.0";
const io_entries = 32;
const flags = 0;

const IoError = error{
    UnsupportedPlatform,
    InvalidLinuxVer,
    SetupError
};

// Setups uo io_uring interface
pub fn setup_io() !IoUring {
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

    return (IoUring.init(io_entries, flags)) catch {
        return error.SetupError;
    };
}

pub fn deinit(ring: *IoUring) void {
    ring.deinit();
}

const FileError = error{
    Read,
    Write,
    Open
};


pub fn read_file(ring: *IoUring, path: []const u8, buffer: *[]const u8) !void {
    const file = std.fs.openFileAbsolute(path, .{}) catch {
        return FileError.Open;
    };
    const fd = file.handle;
    file.read(buffer) catch {
        return FileError.Read;
    };
    _ = try ring.read(0x22222222, fd, .{ .buffer = buffer[0..] }, 0);
}

// pub fn accept_io(io: IoUring) !void {
//     var sqe = try io.get_sqe();
//     return;
/}
