module Hancock
  class Callback
    include Hancock::Helpers
    extend Hancock::Helpers

    attr_accessor :name, :url, :active, :logging, :envelope_events,
      :recipient_events, :include_documents, :all_users, :identifier

    AttributeToDocusignConfigMap = {
      name: "name",
      url: "urlToPublishTo",
      active: "allowEnvelopePublish",
      logging: "enableLog",
      envelope_events: "envelopeEvents",
      recipient_events: "recipientEvents",
      include_documents: "includeDocuments",
      all_users: "allUsers",
      identifier: "connectId"
    }

    def self.all
      response = send_get_request("/accounts/#{Hancock.account_id}/connect")["configurations"]
      response.map { |config| from_docusign_response(config) }
    end

    def self.from_docusign_response(response)
      attributes_hash = AttributeToDocusignConfigMap.inject({}) { |hsh, (attribute, config)|
        hsh[attribute] = response[config]; hsh
      }
      new(attributes_hash)
    end

    def self.find_by_name(name)
      all.detect { |callback| callback.name == name }
    end

    def initialize(options = {})
      @name = options[:name]
      @url = options[:url]
      @active = options[:active].to_s == 'true'
      @logging = options[:logging].to_s == 'true'
      @envelope_events = options[:envelope_events]
      @recipient_events = options[:recipient_events]
      @include_documents = options[:include_documents].to_s == 'true'
      @all_users = options[:all_users].to_s == 'true'
      @identifier = options[:identifier]
    end

    def ==(other)
      AttributeToDocusignConfigMap.keys.all? { |key|
        self.send(key) == other.send(key)
      }
    end

    def save!
      existing = self.class.find_by_name(name)
      post_params = AttributeToDocusignConfigMap.inject({}) { |hsh, (attribute, config)|
        hsh[config] = self.send(attribute); hsh
      }.merge(useSoapInterface: false)

      url = "/accounts/#{Hancock.account_id}/connect"
      headers = get_headers({ 'Content-Type' => 'application/json' })
      response = if existing
        send_put_request(url, post_params.to_json, headers)
      else
        send_post_request(url, post_params.to_json, headers)
      end
      self.identifier = response['connectId']
    end
  end
end
