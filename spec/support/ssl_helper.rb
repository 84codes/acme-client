require 'yaml'

module SSLHelper
  class KeyStash
    KEYSTASH_PATH = File.join(__dir__, '../fixtures/keystash.yml')

    def initialize
      @keystash = load
      @iter = @keystash.each
    end

    def next
      @iter.next
    rescue StopIteration
      @keystash << generate_key
      save
      @keystash.last
    end

    def generate_key
      case (rand * 4).to_i
      when 0
        OpenSSL::PKey::RSA.new(2048)
      when 1
        generate_ecdsa_key('prime256v1')
      when 2
        generate_ecdsa_key('secp384r1')
      when 3
        OpenSSL::PKey::RSA.new(2048)
        # TODO: ECDSA curve P-521 not allowed at the moment.
        # generate_ecdsa_key('secp521r1')
      end
    end

    def generate_ecdsa_key(curve)
      k = OpenSSL::PKey::EC.generate(curve)
      Acme::Client::CertificateRequest::ECKeyPatch.new(k)
    end

    private

    def load
      if File.exist?(KEYSTASH_PATH)
        YAML.load_file(KEYSTASH_PATH).shuffle.map do |pem|
          begin
            OpenSSL::PKey::RSA.new(pem)
          rescue StandardError
            Acme::Client::CertificateRequest::ECKeyPatch.new(pem)
          end
        end
      else
        []
      end
    end

    def save
      File.write(KEYSTASH_PATH, YAML.dump(@keystash.map(&:to_pem)))
    end
  end

  KEYSTASH = KeyStash.new

  def generate_private_key
    KEYSTASH.next
  end

  def generate_csr(common_name, private_key)
    request = OpenSSL::X509::Request.new
    request.subject = OpenSSL::X509::Name.new(
      [
        [
          'CN',
          common_name,
          OpenSSL::ASN1::UTF8STRING
        ]
      ]
    )

    Acme::Client::Util.set_public_key(request, private_key)
    request.sign(private_key, OpenSSL::Digest::SHA256.new)
    request
  end

  # Verify a CSR's signature.
  #
  # csr  - A OpenSSL::X509::Request instance.
  # priv - An OpenSSL::PKey::EC or OpenSSL::PKey::RSA instance.
  #
  # Returns boolean.
  def verify_csr(csr, priv)
    case priv
    when OpenSSL::PKey::EC
      csr.verify(priv)
    when OpenSSL::PKey::RSA
      csr.verify(priv.public_key)
    else
      raise ArgumentError, 'priv must be EC or RSA'
    end
  end

  # Export a private key's public key in DER format.
  #
  # priv - An OpenSSL::PKey::EC or OpenSSL::PKey::RSA instance.
  #
  # Returns a String.
  def public_key_to_pem(private_key)
    case private_key
    when OpenSSL::PKey::EC
      # TODO: Ruby 2.7 shenanigans
      if OpenSSL::PKey::EC.method_defined?(:to_pem)
        private_key.to_pem
      else
        dup = OpenSSL::PKey::EC.new(private_key.to_der)
        dup.private_key = nil
        dup.to_pem
      end
    when OpenSSL::PKey::RSA
      private_key.public_key.to_pem
    else
      raise ArgumentError, 'private_key must be EC or RSA'
    end
  end
end
