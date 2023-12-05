module Tapyrus
  module JWS
    module_function

    ALGO = 'ES256K'
    CURVE_NAME = 'secp256k1'

    # Encode data as JWS format.
    #
    # @param data [Object] The data to be encoded as JWS.
    # @param private_key_hex [String] private key as hex string
    # @return [String] JWS signed with the specified private key
    def encode(data, private_key_hex)
      parameters = { use: 'sig', alg: ALGO }
      sequence =
        OpenSSL::ASN1.Sequence(
          [
            OpenSSL::ASN1.Integer(1),
            OpenSSL::ASN1.OctetString(OpenSSL::BN.new(private_key_hex, 16).to_s(2)),
            OpenSSL::ASN1.ObjectId(CURVE_NAME, 0, :EXPLICIT),
            OpenSSL::ASN1.BitString(
              ECDSA::Format::PointOctetString.encode(point_for(private_key_hex), compression: false),
              1,
              :EXPLICIT
            )
          ]
        )
      ec_key = OpenSSL::PKey::EC.new(sequence.to_der)
      jwk = JWT::JWK.new(ec_key, parameters)
      jwks_hash = JWT::JWK::Set.new(jwk).export(include_private: false)
      JWT.encode(data, jwk.signing_key, jwk[:alg], { typ: 'JWT', algo: ALGO, jwk: jwks_hash })
    end

    # Decode JWS to JSON object
    #
    # @param data [Object] The data to be decoded
    # @return [Array[JSON]] JSON objects representing JWS header and payload.
    # @raise [JWT::VerificationError] raise if verification signature failed
    # @raise [JWT::DecodeError] raise if no jwk key found in header
    # @raise [JWT::DecodeError] raise if jwk kty header is not EC
    # @raise [JWT::DecodeError] raise if jwk crv header is not P-256K
    # @raise [JWT::DecodeError] raise if jwk use header is not sig
    # @raise [JWT::DecodeError] raise if jwk alg header is not ES256K
    def decode(data)
      jwt_claims, header = JWT.decode(data, nil, false, { algorithm: ALGO })
      jwks_hash = header.dig('jwk', 'keys')
      raise JWT::DecodeError, 'No jwk key found in header' unless jwks_hash
      validate_header!(jwks_hash)
      jwks = JWT::JWK::Set.new(jwks_hash)
      JWT.decode(data, nil, true, { algorithm: ALGO, jwks: jwks, allow_nil_kid: true })
    end

    def validate_header!(jwks)
      jwk = jwks.first
      raise JWT::DecodeError, 'No jwk key found in header' unless jwk
      raise JWT::DecodeError, 'kty must be "EC"' if jwk['kty'] && jwk['kty'] != 'EC'
      raise JWT::DecodeError, 'crv must be "P-256K"' if jwk['crv'] && jwk['crv'] != 'P-256K'
      raise JWT::DecodeError, 'use must be "sig"' if jwk['use'] && jwk['use'] != 'sig'
      raise JWT::DecodeError, 'alg must be "ES256K"' if jwk['alg'] && jwk['alg'] != 'ES256K'
    end

    # Return point object that represents rG
    #
    # @param r_hex [String] r value as hex string
    # @return [ECDSA::Point] The point that represents r * G
    def point_for(r_hex)
      r = ECDSA::Format::IntegerOctetString.decode([r_hex].pack('H*'))
      g = ECDSA::Group::Secp256k1.generator
      g * r
    end
  end
end
