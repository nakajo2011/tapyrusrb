module Bitcoin

  # Block Header
  class BlockHeader

    attr_accessor :hash
    attr_accessor :version
    attr_accessor :prev_hash
    attr_accessor :merkle_root
    attr_accessor :time
    attr_accessor :bits
    attr_accessor :nonce

    def initialize(version, prev_hash, merkle_root, time, bits, nonce)
      @version = version
      @prev_hash = prev_hash
      @merkle_root = merkle_root
      @time = time
      @bits = bits
      @nonce = nonce
      @hash = calc_hash
    end

    def self.parse_from_payload(payload)
      version, prev_hash, merkle_root, time, bits, nonce = payload.unpack('Va32a32VVV')
      new(version, prev_hash.reverse.bth, merkle_root.reverse.bth, time, bits, nonce)
    end

    def to_payload
      [version, prev_hash.htb.reverse, merkle_root.htb.reverse, time, bits, nonce].pack('Va32a32VVV')
    end

    private

    def calc_hash
      Bitcoin.double_sha256(to_payload).reverse.bth
    end

  end

end