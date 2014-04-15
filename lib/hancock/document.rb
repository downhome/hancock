module Hancock
  class Document < Hancock::Base

    #
    # file:       #<File:/tmp/whatever.pdf>,
    # data:       'Base64 Encoded String', # required if no file, invalid if file
    # name:       'whatever.pdf', # optional if file, defaults to basename
    # extension:  'pdf', # optional if file, defaults to path extension
    # identifier: 'my_document_3', # optional, generates if not given
    # 

    attr_accessor :file, :data, :name, :extension, :identifier

    validates :name, :extension, presence: true
    validates :file, type: :file, allow_nil: true
    validates :data, type: :string, presence: lambda{ |inst| !inst.file }


    #
    # skip validations if 'run_validations' is false
    #
    def initialize(attributes = {}, run_validations = true) 
      @file       = attributes[:file] 
      @data       = attributes[:data]
      @name       = attributes[:name]       || generate_name()
      @extension  = attributes[:extension]  || generate_extension()
      @identifier = attributes[:identifier] || generate_identifier()

      self.validate! if run_validations
    end

    def to_request
      { documentId: identifier, name: name }
    end

    def data_for_request
      file.nil? ? data : IO.read(file)      
    end

    private
      def generate_name
        File.basename(@file, '.*') if @file
      end

      def generate_extension
        File.basename(@file).split('.').last if @file
      end

  end
end