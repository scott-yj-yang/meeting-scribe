import Testing
import Foundation
@testable import MeetingScribe

@Suite("FFmpegLocator")
struct FFmpegLocatorTests {

    /// Builds a throwaway directory tree with fake `ffmpeg` binaries.
    private struct Fixture {
        let root: URL
        let fm = FileManager.default

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("FFmpegLocatorTests-\(UUID().uuidString)")
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func directory(_ name: String) throws -> URL {
            let dir = root.appendingPathComponent(name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        @discardableResult
        func ffmpeg(in dir: URL, executable: Bool = true) throws -> URL {
            let url = dir.appendingPathComponent("ffmpeg")
            try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
            return url
        }

        func cleanUp() { try? fm.removeItem(at: root) }
    }

    @Test("returns nil when ffmpeg is not installed")
    func missingFFmpegResolvesToNil() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let empty = try fixture.directory("empty")
        #expect(FFmpegLocator.resolve(searchPaths: [empty.path], environmentPath: nil) == nil)
    }

    @Test("ignores a non-executable file named ffmpeg")
    func nonExecutableIsIgnored() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let dir = try fixture.directory("nonexec")
        try fixture.ffmpeg(in: dir, executable: false)
        #expect(FFmpegLocator.resolve(searchPaths: [dir.path], environmentPath: nil) == nil)
    }

    @Test("finds an executable ffmpeg in a search path")
    func findsExecutable() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let dir = try fixture.directory("bin")
        let binary = try fixture.ffmpeg(in: dir)
        #expect(FFmpegLocator.resolve(searchPaths: [dir.path], environmentPath: nil) == binary)
    }

    /// Intel Macs install to /usr/local/bin — the previously hardcoded
    /// /opt/homebrew/bin path never found them.
    @Test("falls through an empty directory to a later search path")
    func laterSearchPathIsUsed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let empty = try fixture.directory("empty")
        let local = try fixture.directory("usr-local-bin")
        let binary = try fixture.ffmpeg(in: local)

        #expect(FFmpegLocator.resolve(
            searchPaths: [empty.path, local.path], environmentPath: nil) == binary)
    }

    @Test("earlier search path wins")
    func searchPathOrderIsHonoured() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let brew = try fixture.directory("opt-homebrew-bin")
        let local = try fixture.directory("usr-local-bin")
        let preferred = try fixture.ffmpeg(in: brew)
        try fixture.ffmpeg(in: local)

        #expect(FFmpegLocator.resolve(
            searchPaths: [brew.path, local.path], environmentPath: nil) == preferred)
    }

    @Test("falls back to PATH when the known locations miss")
    func pathFallbackIsUsed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let empty = try fixture.directory("empty")
        let custom = try fixture.directory("custom")
        let binary = try fixture.ffmpeg(in: custom)

        #expect(FFmpegLocator.resolve(
            searchPaths: [], environmentPath: "\(empty.path):\(custom.path)") == binary)
    }

    @Test("returns nil with no search paths and no PATH")
    func noSourcesResolvesToNil() {
        #expect(FFmpegLocator.resolve(searchPaths: [], environmentPath: nil) == nil)
    }
}
