#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

import Venice
import Core
import CLibdill
import CDsock

let DSOCK_BTLS_DEFAULT  =
    DSOCK_BTLS_PROTO_DEFAULT |
    DSOCK_BTLS_DHEPARAMS_NONE |
    DSOCK_BTLS_ECDHECURVE_AUTO |
    DSOCK_BTLS_CIPHERS_DEFAULT |
    DSOCK_BTLS_VERIFY_DEPTH_DEFAULT |
    DSOCK_BTLS_PREFER_CIPHERS_SERVER |
    DSOCK_BTLS_CLEAR_KEYS

// TODO: Create TCP errors
public enum TLSError : Error {}

public final class TLSHost : Handle, Host {
    public let ip: IP
    private let socket: Int32
    
    init(handle: HandleDescriptor, socket: Int32, ip: IP) {
        self.ip = ip
        self.socket = socket
        super.init(handle: handle)
    }
    
    deinit {
        try? close()
    }
    
    public convenience init(
        ip: IP,
        certificatePath: String,
        keyPath: String,
        backlog: Int,
        reusePort: Bool
    ) throws {
        var address = ip.address
        var result = tcp_listen(&address, Int32(backlog))
        
        // TODO: Set reusePort
        
        guard result != -1 else {
            switch errno {
            default:
                throw SystemError.lastOperationError
            }
        }
        
        let socket = result
        var keyPair = btls_kp()
        var certificateLength = 0
        var keyLength = 0
        let certificate = btls_loadfile(certificatePath, &certificateLength, nil)
        let key = btls_loadfile(keyPath, &keyLength, nil)
        
        result = btls_kp(&keyPair, certificate, certificateLength, key, keyLength)
        
        certificate?.deallocate(capacity: 1)
        key?.deallocate(capacity: 1)
        
        guard result != -1 else {
            switch errno {
            default:
                throw SystemError.lastOperationError
            }
        }
        
        result = btls_attach_server(socket, UInt64(DSOCK_BTLS_DEFAULT), 0, &keyPair, 1, nil, nil)
        
        guard result != -1 else {
            switch errno {
            default:
                throw SystemError.lastOperationError
            }
        }
        
        self.init(handle: result, socket: socket, ip: ip)
    }
    
    public convenience init(
        host: String = "",
        port: Int = 8080,
        certificatePath: String,
        keyPath: String,
        backlog: Int = 128,
        reusePort: Bool = false
    ) throws {
        let ip: IP
        
        if host == "" {
            ip = try IP(port: port)
        } else {
            ip = try IP(local: host, port: port)
        }
        
        try self.init(
            ip: ip,
            certificatePath: certificatePath,
            keyPath: keyPath,
            backlog: backlog,
            reusePort: reusePort
        )
    }
    
    public func accept(deadline: Deadline) throws -> DuplexStream {
        var address = ipaddr()
        var result = tcp_accept(handle, &address, deadline.value)
        
        guard result != -1 else {
            switch errno {
            default:
                throw SystemError.lastOperationError
            }
        }
        
        let socket = result
        result = btls_attach_accept(socket, handle)
        
        guard result != -1 else {
            switch errno {
            default:
                throw SystemError.lastOperationError
            }
        }
        
        return TLSStream(handle: result, socket: socket, ip: IP(address: &address))
    }
}