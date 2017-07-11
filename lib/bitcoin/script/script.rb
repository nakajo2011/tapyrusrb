module Bitcoin

  # bitcoin script
  class Script
    include Bitcoin::Opcodes

    # witness version
    WITNESS_VERSION = 0x00

    # Maximum script length in bytes
    MAX_SCRIPT_SIZE = 10000

    # Maximum number of public keys per multisig
    MAX_PUBKEYS_PER_MULTISIG = 20

    # Maximum number of non-push operations per script
    MAX_OPS_PER_SCRIPT = 201

    # Maximum number of bytes pushable to the stack
    MAX_SCRIPT_ELEMENT_SIZE = 520

    # Threshold for nLockTime: below this value it is interpreted as block number, otherwise as UNIX timestamp.
    LOCKTIME_THRESHOLD = 500000000

    attr_accessor :chunks

    def initialize
      @chunks = []
    end

    # generate P2PKH script
    def self.to_p2pkh(pubkey_hash)
      new << OP_DUP << OP_HASH160 << pubkey_hash << OP_EQUALVERIFY << OP_CHECKSIG
    end

    # generate P2WPKH script
    def self.to_p2wpkh(pubkey_hash)
      new << WITNESS_VERSION << pubkey_hash
    end

    # generate m of n multisig p2sh script
    # @param [String] m the number of signatures required for multisig
    # @param [Array] pubkeys array of public keys that compose multisig
    # @return [Script, Script] first element is p2sh script, second one is redeem script.
    def self.to_p2sh_multisig_script(m, pubkeys)
      redeem_script = to_multisig_script(m, pubkeys)
      p2sh_script = new << OP_HASH160 << redeem_script.to_hash160 << OP_EQUAL
      [p2sh_script, redeem_script]
    end

    # generate m of n multisig script
    # @param [String] m the number of signatures required for multisig
    # @param [Array] pubkeys array of public keys that compose multisig
    # @return [Script] multisig script.
    def self.to_multisig_script(m, pubkeys)
      new << m << pubkeys << pubkeys.size << OP_CHECKMULTISIG
    end

    # generate p2wsh script for +redeem_script+
    # @param [Script] redeem_script target redeem script
    # @param [Script] p2wsh script
    def self.to_p2wsh(redeem_script)
      new << WITNESS_VERSION << redeem_script.to_sha256
    end

    # generate script from string.
    def self.from_string(string)
      script = new
      string.split(' ').each do |v|
        opcode = Opcodes.name_to_opcode(v)
        if opcode
          script << opcode
        else
          v = v.to_i if v =~ /^\d/ && Opcodes.small_int_to_opcode(v.to_i)
          script << v
        end
      end
      script
    end

    def self.parse_from_payload(payload)
      s = new
      buf = StringIO.new(payload)
      until buf.eof?
        opcode = buf.read(1)
        if opcode?(opcode)
          s << opcode.ord
        else
          pushcode = opcode.ord
          len = case pushcode
                when OP_PUSHDATA1
                  buf.read(1)
                when OP_PUSHDATA2
                  buf.read(2)
                when OP_PUSHDATA4
                  buf.read(4)
                else
                  pushcode if pushcode < OP_PUSHDATA1
                end
          s << buf.read(len).bth if len
        end
      end
      s
    end

    def to_payload
      chunks.join
    end

    def to_addr
      return p2pkh_addr if p2pkh?
      return p2wpkh_addr if p2wpkh?
      return p2wsh_addr if p2wsh?
      return p2sh_addr if p2sh?
    end

    # whether this script is a P2PKH format script.
    def p2pkh?
      return false unless chunks.size == 5
      [OP_DUP, OP_HASH160, OP_EQUALVERIFY, OP_CHECKSIG] ==
          (chunks[0..1]+ chunks[3..4]).map(&:ord) && chunks[2].bytesize == 21
    end

    # whether this script is a P2WPKH format script.
    def p2wpkh?
      return false unless chunks.size == 2
      chunks[0].ord == WITNESS_VERSION && chunks[1].bytesize == 21
    end

    def p2wsh?
      return false unless chunks.size == 2
      chunks[0].ord == WITNESS_VERSION && chunks[1].bytesize == 33
    end

    def p2sh?
      return false unless chunks.size == 3
      OP_HASH160 == chunks[0].ord && OP_EQUAL == chunks[2].ord && chunks[1].bytesize == 21
    end

    # whether data push only script which dose not include other opcode
    def push_only?
      chunks.each do |c|
        return false if Script.opcode?(c)
      end
      true
    end

    # whether this script has witness program.
    def witness_program?
      p2wpkh? || p2wsh?
    end

    # append object to payload
    def <<(obj)
      if obj.is_a?(Integer)
        append_opcode(obj)
      elsif obj.is_a?(String)
        append_data(obj.b)
      elsif obj.is_a?(Array)
        obj.each { |o| self.<< o}
        self
      end
    end

    # append opcode to payload
    # @param [Integer] opcode append opcode which defined by Bitcoin::Opcodes
    # @return [Script] return self
    def append_opcode(opcode)
      opcode = Opcodes.small_int_to_opcode(opcode) if -1 <= opcode && opcode <= 16
      raise ArgumentError, "specified invalid opcode #{opcode}." unless Opcodes.defined?(opcode)
      chunks << opcode.chr
      self
    end

    # append data to payload with pushdata opcode
    # @param [String] data append data. this data is not binary
    # @return [Script] return self
    def append_data(data)
      data = data.htb
      size = data.bytesize
      header = if size < OP_PUSHDATA1
                 [size].pack('C')
               elsif size < 0xff
                 [OP_PUSHDATA1, size].pack('CC')
               elsif size < 0xffff
                 [OP_PUSHDATA2, size].pack('Cv')
               elsif size < 0xffffffff
                 [OP_PUSHDATA4, size].pack('CV')
               else
                 raise ArgumentError, 'data size is too big.'
               end
      chunks << (header + data)
      self
    end

    def to_s
      chunks.map { |c|
        if Script.opcode?(c)
          v = Opcodes.opcode_to_small_int(c.ord)
          v ? v : Opcodes.opcode_to_name(c.ord)
        else
          Script.pushed_data(c)
        end
      }.join(' ')
    end

    # determine where the data is an opcode.
    def self.opcode?(data)
      !pushdata?(data)
    end

    # determine where the data is a pushdadta.
    def self.pushdata?(data)
      # the minimum value of opcode is pushdata operation.
      first_byte = data.each_byte.next
      OP_0 < first_byte && first_byte <= OP_PUSHDATA4
    end

    # get pushed data in pushdata bytes
    def self.pushed_data(data)
      opcode = data.each_byte.next
      offset = 1
      case opcode
      when OP_PUSHDATA1
        offset += 1
      when OP_PUSHDATA2
        offset += 2
      when OP_PUSHDATA4
        offset += 4
      end
      data[offset..-1].bth
    end

    # generate sha-256 hash for payload
    def to_sha256
      Bitcoin.sha256(to_payload).bth
    end

    # generate hash160 hash for payload
    def to_hash160
      Bitcoin.hash160(to_payload.bth)
    end

    # script size
    def size
      to_payload.bytesize
    end

    private

    # generate p2pkh address. if script dose not p2pkh, return nil.
    def p2pkh_addr
      return nil unless p2pkh?
      hash160 = Script.pushed_data(chunks[2])
      return nil unless hash160.htb.bytesize == 20
      hex = Bitcoin.chain_params.address_version + hash160
      Bitcoin.encode_base58_address(hex)
    end

    # generate p2wpkh address. if script dose not p2wpkh, return nil.
    def p2wpkh_addr
      p2wpkh? ? bech32_addr : nil
    end

    # generate p2sh address. if script dose not p2sh, return nil.
    def p2sh_addr
      return nil unless p2sh?
      hash160 = Script.pushed_data(chunks[1])
      return nil unless hash160.htb.bytesize == 20
      hex = Bitcoin.chain_params.p2sh_version + hash160
      Bitcoin.encode_base58_address(hex)
    end

    # generate p2wsh address. if script dose not p2wsh, return nil.
    def p2wsh_addr
      p2wsh? ? bech32_addr : nil
    end

    # return bech32 address for payload
    def bech32_addr
      segwit_addr = Bech32::SegwitAddr.new
      segwit_addr.hrp = Bitcoin.chain_params.bech32_hrp
      segwit_addr.script_pubkey = to_payload.bth
      segwit_addr.addr
    end

  end

end