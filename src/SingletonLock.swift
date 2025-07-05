import AppKit

final actor SingletonLock {
	enum Error: Swift.Error {
		case instanceAlreadyRunning
		case lockFileError(String)
	}

	private let lockFilePath = NSTemporaryDirectory().appending("com.acsandmann.menuanywhere.lock")
	private var lockFileDescriptor: CInt

	init() throws {
		let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)
		if fd == -1 {
			throw Error.lockFileError(String(cString: strerror(errno)))
		}

		if flock(fd, LOCK_EX | LOCK_NB) == -1 {
			close(fd)
			guard errno == EWOULDBLOCK else {
				throw Error.lockFileError(
					"Failed to acquire lock: \(String(cString: strerror(errno)))")
			}
			throw Error.instanceAlreadyRunning
		}

		lockFileDescriptor = fd
	}

	deinit {
		flock(lockFileDescriptor, LOCK_UN)
		close(lockFileDescriptor)
		try? FileManager.default.removeItem(atPath: lockFilePath)
	}
}
