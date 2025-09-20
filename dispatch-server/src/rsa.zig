const std = @import("std");
const ff = std.crypto.ff;

const chunk_data_size = 245;
const padding_size = 11;
const padded_size = chunk_data_size + padding_size;
pub const sign_size: usize = 64;

const client_public_key_der = @embedFile("client_public_key.der");
const server_private_key_der = @embedFile("server_private_key.der");

var client_public_key: ?PublicKey = null;
var server_private_key: ?KeyPair = null;

pub fn paddedLength(plaintext_len: usize) usize {
    return (std.math.divCeil(usize, plaintext_len, chunk_data_size) catch unreachable) * padded_size;
}

pub fn encrypt(plaintext: []const u8, output: []u8) void {
    const numChunks = std.math.divCeil(usize, plaintext.len, chunk_data_size) catch unreachable;
    const key = clientPublicKey();

    for (0..numChunks) |n| {
        const plainChunk = plaintext[n * chunk_data_size .. @min((n + 1) * chunk_data_size, plaintext.len)];
        _ = key.encryptPkcsv1_5(plainChunk, output[n * padded_size .. (n + 1) * padded_size]) catch unreachable;
    }
}

pub fn decrypt(ciphertext: []const u8, output: []u8) ![]const u8 {
    return try serverPrivateKey().decryptPkcsv1_5(ciphertext, output);
}

pub fn sign(plaintext: []const u8, output: *[sign_size]u8) void {
    _ = serverPrivateKey().signPkcsv1_5(std.crypto.hash.sha2.Sha256, plaintext, output) catch unreachable;
}

inline fn clientPublicKey() *PublicKey {
    if (client_public_key == null) {
        client_public_key = PublicKey.fromDer(client_public_key_der) catch @panic("client_public_key.der is invalid");
    }

    return &client_public_key.?;
}

inline fn serverPrivateKey() *KeyPair {
    if (server_private_key == null) {
        server_private_key = KeyPair.fromDer(server_private_key_der) catch @panic("server_private_key.der is invalid");
    }

    return &server_private_key.?;
}

const max_modulus_bits = 4096;
const max_modulus_len = max_modulus_bits / 8;

const Modulus = std.crypto.ff.Modulus(max_modulus_bits);
const Fe = Modulus.Fe;
const Index = usize;

pub const ValueError = error{
    Modulus,
    Exponent,
};

const PublicKey = struct {
    /// `n`
    modulus: Modulus,
    /// `e`
    public_exponent: Fe,

    pub const FromBytesError = ValueError || ff.OverflowError || ff.FieldElementError || ff.InvalidModulusError || error{InsecureBitCount};

    pub fn fromBytes(mod: []const u8, exp: []const u8) FromBytesError!PublicKey {
        const modulus = try Modulus.fromBytes(mod, .big);
        const public_exponent = try Fe.fromBytes(modulus, exp, .big);

        if (std.debug.runtime_safety) {
            // > the RSA public exponent e is an integer between 3 and n - 1 satisfying
            // > GCD(e,\lambda(n)) = 1, where \lambda(n) = LCM(r_1 - 1, ..., r_u - 1)
            const e_v = public_exponent.toPrimitive(u32) catch return error.Exponent;
            if (!public_exponent.isOdd()) return error.Exponent;
            if (e_v < 3) return error.Exponent;
            if (modulus.v.compare(public_exponent.v) == .lt) return error.Exponent;
        }

        return .{ .modulus = modulus, .public_exponent = public_exponent };
    }

    pub fn fromDer(bytes: []const u8) (Parser.Error || FromBytesError)!PublicKey {
        var parser = Parser{ .bytes = bytes };

        const seq = try parser.expectSequence();
        defer parser.seek(seq.slice.end);

        const modulus = try parser.expectPrimitive(.integer);
        const pub_exp = try parser.expectPrimitive(.integer);

        try parser.expectEnd(seq.slice.end);
        try parser.expectEnd(bytes.len);

        return try fromBytes(parser.view(modulus), parser.view(pub_exp));
    }

    pub fn encryptPkcsv1_5(pk: PublicKey, msg: []const u8, out: []u8) ![]const u8 {
        // align variable names with spec
        const k = byteLen(pk.modulus.bits());
        if (out.len < k) return error.BufferTooSmall;
        if (msg.len > k - 11) return error.MessageTooLong;

        // EM = 0x00 || 0x02 || PS || 0x00 || M.
        var em = out[0..k];
        em[0] = 0;
        em[1] = 2;

        const ps = em[2..][0 .. k - msg.len - 3];
        // Section: 7.2.1
        // PS consists of pseudo-randomly generated nonzero octets.
        for (ps) |*v| {
            v.* = std.crypto.random.uintLessThan(u8, 0xff) + 1;
        }

        em[em.len - msg.len - 1] = 0;
        @memcpy(em[em.len - msg.len ..][0..msg.len], msg);

        const m = try Fe.fromBytes(pk.modulus, em, .big);
        const e = try pk.modulus.powPublic(m, pk.public_exponent);
        try e.toBytes(em, .big);
        return em;
    }
};

fn byteLen(bits: usize) usize {
    return std.math.divCeil(usize, bits, 8) catch unreachable;
}

const SecretKey = struct {
    /// `d`
    private_exponent: Fe,

    pub const FromBytesError = ValueError || ff.OverflowError || ff.FieldElementError;

    pub fn fromBytes(n: Modulus, exp: []const u8) FromBytesError!SecretKey {
        const d = try Fe.fromBytes(n, exp, .big);
        if (std.debug.runtime_safety) {
            // > The RSA private exponent d is a positive integer less than n
            // > satisfying e * d == 1 (mod \lambda(n)),
            if (!d.isOdd()) return error.Exponent;
            if (d.v.compare(n.v) != .lt) return error.Exponent;
        }

        return .{ .private_exponent = d };
    }
};

const KeyPair = struct {
    public: PublicKey,
    secret: SecretKey,

    pub const FromDerError = PublicKey.FromBytesError || SecretKey.FromBytesError || Parser.Error || error{ KeyMismatch, InvalidVersion };

    pub fn fromDer(bytes: []const u8) FromDerError!KeyPair {
        var parser = Parser{ .bytes = bytes };
        const seq = try parser.expectSequence();
        const version = try parser.expectInt(u8);

        const mod = try parser.expectPrimitive(.integer);
        const pub_exp = try parser.expectPrimitive(.integer);
        const sec_exp = try parser.expectPrimitive(.integer);

        const public = try PublicKey.fromBytes(parser.view(mod), parser.view(pub_exp));
        const secret = try SecretKey.fromBytes(public.modulus, parser.view(sec_exp));

        const prime1 = try parser.expectPrimitive(.integer);
        const prime2 = try parser.expectPrimitive(.integer);
        const exp1 = try parser.expectPrimitive(.integer);
        const exp2 = try parser.expectPrimitive(.integer);
        const coeff = try parser.expectPrimitive(.integer);
        _ = .{ exp1, exp2, coeff };

        switch (version) {
            0 => {},
            1 => {
                _ = try parser.expectSequenceOf();
                while (!parser.eof()) {
                    _ = try parser.expectSequence();
                    const ri = try parser.expectPrimitive(.integer);
                    const di = try parser.expectPrimitive(.integer);
                    const ti = try parser.expectPrimitive(.integer);
                    _ = .{ ri, di, ti };
                }
            },
            else => return error.InvalidVersion,
        }

        try parser.expectEnd(seq.slice.end);
        try parser.expectEnd(bytes.len);

        if (std.debug.runtime_safety) {
            const p = try Fe.fromBytes(public.modulus, parser.view(prime1), .big);
            const q = try Fe.fromBytes(public.modulus, parser.view(prime2), .big);

            // check that n = p * q
            const expected_zero = public.modulus.mul(p, q);
            if (!expected_zero.isZero()) return error.KeyMismatch;
        }

        return .{ .public = public, .secret = secret };
    }

    pub fn signPkcsv1_5(kp: KeyPair, comptime Hash: type, msg: []const u8, out: []u8) !PKCS1v1_5(Hash).Signature {
        var st = try signerPkcsv1_5(kp, Hash);
        st.update(msg);
        return try st.finalize(out);
    }

    pub fn signerPkcsv1_5(kp: KeyPair, comptime Hash: type) !PKCS1v1_5(Hash).Signer {
        return PKCS1v1_5(Hash).Signer.init(kp);
    }

    pub fn decryptPkcsv1_5(kp: KeyPair, ciphertext: []const u8, out: []u8) ![]const u8 {
        const k = byteLen(kp.public.modulus.bits());
        if (out.len < k) return error.BufferTooSmall;

        const em = out[0..k];

        const m = try Fe.fromBytes(kp.public.modulus, ciphertext, .big);
        const e = try kp.public.modulus.pow(m, kp.secret.private_exponent);
        try e.toBytes(em, .big);

        const msg_start = ct.lastIndexOfScalar(em, 0) orelse em.len;
        return em[msg_start + 1 ..];
    }

    pub fn encrypt(kp: KeyPair, plaintext: []const u8, out: []u8) !void {
        const n = kp.public.modulus;
        const k = byteLen(n.bits());
        if (plaintext.len > k) return error.MessageTooLong;

        const msg_as_int = try Fe.fromBytes(n, plaintext, .big);
        const enc_as_int = try n.pow(msg_as_int, kp.secret.private_exponent);
        try enc_as_int.toBytes(out, .big);
    }
};

fn PKCS1v1_5(comptime Hash: type) type {
    return struct {
        const PkcsT = @This();
        pub const Signature = struct {
            bytes: []const u8,

            const Self = @This();

            pub fn verifier(self: Self, public_key: PublicKey) !Verifier {
                return Verifier.init(self, public_key);
            }

            pub fn verify(self: Self, msg: []const u8, public_key: PublicKey) !void {
                var st = Verifier.init(self, public_key);
                st.update(msg);
                return st.verify();
            }
        };

        pub const Signer = struct {
            h: Hash,
            key_pair: KeyPair,

            fn init(key_pair: KeyPair) Signer {
                return .{
                    .h = Hash.init(.{}),
                    .key_pair = key_pair,
                };
            }

            pub fn update(self: *Signer, data: []const u8) void {
                self.h.update(data);
            }

            pub fn finalize(self: *Signer, out: []u8) !PkcsT.Signature {
                const k = byteLen(self.key_pair.public.modulus.bits());
                if (out.len < k) return error.BufferTooSmall;

                var hash: [Hash.digest_length]u8 = undefined;
                self.h.final(&hash);

                const em = try emsaEncode(hash, out[0..k]);
                try self.key_pair.encrypt(em, em);
                return .{ .bytes = em };
            }
        };

        pub const Verifier = struct {
            h: Hash,
            sig: PkcsT.Signature,
            public_key: PublicKey,

            fn init(sig: PkcsT.Signature, public_key: PublicKey) Verifier {
                return Verifier{
                    .h = Hash.init(.{}),
                    .sig = sig,
                    .public_key = public_key,
                };
            }

            pub fn update(self: *Verifier, data: []const u8) void {
                self.h.update(data);
            }

            pub fn verify(self: *Verifier) !void {
                const pk = self.public_key;
                const s = try Fe.fromBytes(pk.modulus, self.sig.bytes, .big);
                const emm = try pk.modulus.powPublic(s, pk.public_exponent);

                var em_buf: [max_modulus_len]u8 = undefined;
                const em = em_buf[0..byteLen(pk.modulus.bits())];
                try emm.toBytes(em, .big);

                var hash: [Hash.digest_length]u8 = undefined;
                self.h.final(&hash);

                var em_buf2: [max_modulus_len]u8 = undefined;
                const expected_em = try emsaEncode(hash, em_buf2[0..byteLen(pk.modulus.bits())]);
                if (!std.mem.eql(u8, expected_em, em)) return error.Inconsistent;
            }
        };

        /// PKCS Encrypted Message Signature Appendix
        fn emsaEncode(hash: [Hash.digest_length]u8, out: []u8) ![]u8 {
            const digest_header = comptime digestHeader();
            const tLen = digest_header.len + Hash.digest_length;
            const emLen = out.len;
            if (emLen < tLen + 11) return error.ModulusTooShort;
            if (out.len < emLen) return error.BufferTooSmall;

            var res = out[0..emLen];
            res[0] = 0;
            res[1] = 1;
            const padding_len = emLen - tLen - 3;
            @memset(res[2..][0..padding_len], 0xff);
            res[2 + padding_len] = 0;
            @memcpy(res[2 + padding_len + 1 ..][0..digest_header.len], digest_header);
            @memcpy(res[res.len - hash.len ..], &hash);

            return res;
        }

        /// DER encoded header. Sequence of digest algo + digest.
        /// TODO: use a DER encoder instead
        fn digestHeader() []const u8 {
            const sha2 = std.crypto.hash.sha2;
            // Section 9.2 Notes 1.
            return switch (Hash) {
                std.crypto.hash.Sha1 => &hexToBytes(
                    \\30 21 30 09 06 05 2b 0e 03 02 1a 05 00 04 14
                ),
                sha2.Sha224 => &hexToBytes(
                    \\30 2d 30 0d 06 09 60 86 48 01 65 03 04 02 04
                    \\05 00 04 1c
                ),
                sha2.Sha256 => &hexToBytes(
                    \\30 31 30 0d 06 09 60 86 48 01 65 03 04 02 01 05 00
                    \\04 20
                ),
                sha2.Sha384 => &hexToBytes(
                    \\30 41 30 0d 06 09 60 86 48 01 65 03 04 02 02 05 00
                    \\04 30
                ),
                sha2.Sha512 => &hexToBytes(
                    \\30 51 30 0d 06 09 60 86 48 01 65 03 04 02 03 05 00
                    \\04 40
                ),
                else => @compileError("unknown Hash " ++ @typeName(Hash)),
            };
        }
    };
}

const ct = struct {
    fn lastIndexOfScalar(slice: []const u8, value: u8) ?usize {
        return std.mem.lastIndexOfScalar(u8, slice, value);
    }

    fn indexOfScalarPos(slice: []const u8, start_index: usize, value: u8) ?usize {
        return std.mem.indexOfScalarPos(u8, slice, start_index, value);
    }

    fn memEql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    fn @"and"(a: bool, b: bool) bool {
        return a and b;
    }

    fn @"or"(a: bool, b: bool) bool {
        return a or b;
    }
};

fn removeNonHex(comptime hex: []const u8) []const u8 {
    var res: [hex.len]u8 = undefined;
    var i: usize = 0;
    for (hex) |c| {
        if (std.ascii.isHex(c)) {
            res[i] = c;
            i += 1;
        }
    }
    return res[0..i];
}

/// For readable copy/pasting from hex viewers.
fn hexToBytes(comptime hex: []const u8) [removeNonHex(hex).len / 2]u8 {
    const hex2 = comptime removeNonHex(hex);
    comptime var res: [hex2.len / 2]u8 = undefined;
    _ = comptime std.fmt.hexToBytes(&res, hex2) catch unreachable;
    return res;
}

const Parser = struct {
    bytes: []const u8,
    index: Index = 0,

    pub const Error = Element.Error || error{
        UnexpectedElement,
        InvalidIntegerEncoding,
        Overflow,
        NonCanonical,
    };

    pub fn expectBool(self: *Parser) Error!bool {
        const ele = try self.expect(.universal, false, .boolean);
        if (ele.slice.len() != 1) return error.InvalidBool;

        return switch (self.view(ele)[0]) {
            0x00 => false,
            0xff => true,
            else => error.InvalidBool,
        };
    }

    pub fn expectOid(self: *Parser) Error![]const u8 {
        const oid = try self.expect(.universal, false, .object_identifier);
        return self.view(oid);
    }

    pub fn expectEnum(self: *Parser, comptime Enum: type) Error!Enum {
        const oid = try self.expectOid();
        return Enum.oids.get(oid) orelse return error.UnknownObjectId;
    }

    pub fn expectInt(self: *Parser, comptime T: type) Error!T {
        const ele = try self.expectPrimitive(.integer);
        const bytes = self.view(ele);

        const info = @typeInfo(T);
        if (info != .int) @compileError(@typeName(T) ++ " is not an int type");
        const Shift = std.math.Log2Int(u8);

        var result: std.meta.Int(.unsigned, info.int.bits) = 0;
        for (bytes, 0..) |b, index| {
            const shifted = @shlWithOverflow(b, @as(Shift, @intCast(index * 8)));
            if (shifted[1] == 1) return error.Overflow;

            result |= shifted[0];
        }

        return @bitCast(result);
    }

    pub fn expectPrimitive(self: *Parser, tag: ?Identifier.Tag) Error!Element {
        var elem = try self.expect(.universal, false, tag);
        if (tag == .integer and elem.slice.len() > 0) {
            if (self.view(elem)[0] == 0) elem.slice.start += 1;
            if (elem.slice.len() > 0 and self.view(elem)[0] == 0) return error.InvalidIntegerEncoding;
        }
        return elem;
    }

    /// Remember to call `expectEnd`
    pub fn expectSequence(self: *Parser) Error!Element {
        return try self.expect(.universal, true, .sequence);
    }

    /// Remember to call `expectEnd`
    pub fn expectSequenceOf(self: *Parser) Error!Element {
        return try self.expect(.universal, true, .sequence_of);
    }

    pub fn expectEnd(self: *Parser, val: usize) Error!void {
        if (self.index != val) return error.NonCanonical; // either forgot to parse end OR an attacker
    }

    pub fn expect(
        self: *Parser,
        class: ?Identifier.Class,
        constructed: ?bool,
        tag: ?Identifier.Tag,
    ) Error!Element {
        if (self.index >= self.bytes.len) return error.EndOfStream;

        const res = try Element.init(self.bytes, self.index);
        if (tag) |e| {
            if (res.identifier.tag != e) return error.UnexpectedElement;
        }
        if (constructed) |e| {
            if (res.identifier.constructed != e) return error.UnexpectedElement;
        }
        if (class) |e| {
            if (res.identifier.class != e) return error.UnexpectedElement;
        }
        self.index = if (res.identifier.constructed) res.slice.start else res.slice.end;
        return res;
    }

    pub fn view(self: Parser, elem: Element) []const u8 {
        return elem.slice.view(self.bytes);
    }

    pub fn seek(self: *Parser, index: usize) void {
        self.index = index;
    }

    pub fn eof(self: *Parser) bool {
        return self.index == self.bytes.len;
    }
};

const Element = struct {
    identifier: Identifier,
    slice: Slice,

    pub const Slice = struct {
        start: Index,
        end: Index,

        pub fn len(self: Slice) Index {
            return self.end - self.start;
        }

        pub fn view(self: Slice, bytes: []const u8) []const u8 {
            return bytes[self.start..self.end];
        }
    };

    pub const Error = error{ InvalidLength, EndOfStream };

    pub fn init(bytes: []const u8, index: Index) Error!Element {
        var stream = std.io.fixedBufferStream(bytes[index..]);
        var reader = stream.reader();

        const identifier = @as(Identifier, @bitCast(try reader.readByte()));
        const size_or_len_size = try reader.readByte();

        var start = index + 2;
        // short form between 0-127
        if (size_or_len_size < 128) {
            const end = start + size_or_len_size;
            if (end > bytes.len) return error.InvalidLength;

            return .{ .identifier = identifier, .slice = .{ .start = start, .end = end } };
        }

        // long form between 0 and std.math.maxInt(u1024)
        const len_size: u7 = @truncate(size_or_len_size);
        start += len_size;
        if (len_size > @sizeOf(Index)) return error.InvalidLength;
        const len = try reader.readVarInt(Index, .big, len_size);
        if (len < 128) return error.InvalidLength; // should have used short form

        const end = std.math.add(Index, start, len) catch return error.InvalidLength;
        if (end > bytes.len) return error.InvalidLength;

        return .{ .identifier = identifier, .slice = .{ .start = start, .end = end } };
    }
};

const Identifier = packed struct(u8) {
    tag: Tag,
    constructed: bool,
    class: Class,

    pub const Class = enum(u2) {
        universal,
        application,
        context_specific,
        private,
    };

    pub const Tag = enum(u5) {
        boolean = 1,
        integer = 2,
        bitstring = 3,
        octetstring = 4,
        null = 5,
        object_identifier = 6,
        real = 9,
        enumerated = 10,
        string_utf8 = 12,
        sequence = 16,
        sequence_of = 17,
        string_numeric = 18,
        string_printable = 19,
        string_teletex = 20,
        string_videotex = 21,
        string_ia5 = 22,
        utc_time = 23,
        generalized_time = 24,
        string_visible = 26,
        string_universal = 28,
        string_bmp = 30,
        _,
    };
};
