describe Hancock::Envelope do
  context 'validations' do
    def association(klass, identifier: nil, validity: true)
      association = klass.new(identifier: identifier)
      allow(association).to receive(:valid?).and_return(validity)
      association
    end

    it { is_expected.to have_valid(:status).when('yay look a status') }
    it { is_expected.not_to have_valid(:status).when('', nil) }
    it { is_expected.to have_valid(:recipients).when([association(Hancock::Recipient)]) }
    it { is_expected.not_to have_valid(:recipients).when([], nil, [:not_a_recipient], [association(Hancock::Recipient, :validity => false)]) }
    it { is_expected.to have_valid(:documents).when([association(Hancock::Document)]) }
    it { is_expected.not_to have_valid(:documents).when([], nil, [:not_a_document], [association(Hancock::Document, :validity => false)]) }

    context 'recipients' do
      it "should validate uniqueness of ids" do
        subject.recipients = [association(Hancock::Recipient, :identifier => 2), association(Hancock::Recipient, :identifier => 2)]
        subject.valid?
        expect(subject.errors[:recipients]).to include("must all be unique")
      end
    end

    context 'documents' do
      it "should validate uniqueness of ids" do
        subject.documents = [association(Hancock::Document, :identifier => 2), association(Hancock::Document, :identifier => 2)]
        subject.valid?
        expect(subject.errors[:documents]).to include("must all be unique")
      end
    end
  end

  context 'with valid envelope' do
    before do
      allow(subject).to receive(:valid?).and_return(true)
      allow(Hancock).to receive(:oauth_token).and_return('AnAmazingOAuthTokenShinyAndPink')
      allow(Hancock).to receive(:account_id).and_return(123456)
    end

    describe '#save' do
      it 'calls #send_envelope with "created" argument' do
        expect(subject).to receive(:send_envelope).with('created')
        subject.save
      end
    end

    describe '#send!' do
      it 'calls #send_envelope with "sent" argument' do
        expect(subject).to receive(:send_envelope).with('sent')
        subject.send!
      end
    end

    describe '#send_envelope' do
      before do
        allow(subject).to receive(:documents_for_params).and_return('the_documents')
        allow(subject).to receive(:documents_for_body).and_return(['hello world'])
        allow(subject).to receive(:signature_requests_for_params).and_return('the_requests')
        allow(subject).to receive(:email).and_return({ :subject => 'fubject', :blurb => 'flurb'})
      end

      it 'should raise exception if envelope is not valid' do
        allow(subject).to receive(:valid?).and_return(false)
        expect {
          subject.send_envelope('foo')
        }.to raise_error(described_class::InvalidEnvelopeError)
      end

      it 'should raise exception if Hancock not configured' do
        allow(Hancock).to receive(:configured?).and_return(false)
        expect {
          subject.send_envelope('foo')
        }.to raise_error(Hancock::ConfigurationMissing)
      end

      context 'document ids' do
        before(:each) do
          stub_envelope_creation('send_envelope', 'envelope_sent')
          allow(subject).to receive(:reload!)
          subject.documents << Hancock::Document.new
          subject.documents << Hancock::Document.new
        end

        it "should add unique positive integer ids on sending" do
          subject.send_envelope('foo')

          expect(subject.documents.map(&:identifier).all?{|x| x.integer? && x > 0}).to be_truthy
          expect(subject.documents.map(&:identifier).uniq.length).to eq(subject.documents.length)
        end

        it "should preserve existing ids" do
          subject.documents[0].identifier = 3
          subject.documents[1].identifier = 4

          subject.send_envelope('foo')

          expect(subject.documents.map(&:identifier)).to eq([3,4])
        end

        it "should preserve existing ids and generate missing ones" do
          subject.documents[1].identifier = 6

          subject.send_envelope('foo')

          expect(subject.documents.map(&:identifier)).to eq([7,6])
        end
      end

      context 'recipient ids' do
        before(:each) do
          stub_envelope_creation('send_envelope', 'envelope_sent')
          allow(subject).to receive(:reload!)
          subject.recipients << Hancock::Recipient.new
          subject.recipients << Hancock::Recipient.new
        end

        it "should add unique positive integer ids on sending" do
          subject.send_envelope('foo')

          expect(subject.recipients.map(&:identifier).all?{|x| x.integer? && x > 0}).to be_truthy
          expect(subject.recipients.map(&:identifier).uniq.length).to eq(subject.recipients.length)
        end

        it "should preserve existing ids" do
          subject.recipients[0].identifier = 3
          subject.recipients[1].identifier = 4

          subject.send_envelope('foo')

          expect(subject.recipients.map(&:identifier)).to eq([3,4])
        end

        it "should preserve existing ids and generate missing ones" do
          subject.recipients[1].identifier = 6

          subject.send_envelope('foo')

          expect(subject.recipients.map(&:identifier)).to eq([7,6])
        end
      end

      context 'successful send' do
        let!(:request_stub) { stub_envelope_creation('send_envelope', 'envelope_sent') }
        before do
          allow(subject).to receive(:reload!)
        end

        it "sends envelope with given status" do
          subject.send_envelope('foo')
          expect(request_stub).to have_been_requested
        end

        it 'calls #reload!' do
          expect(subject).to receive(:reload!)
          subject.send_envelope('foo')
        end

        it 'sets the identifier to whatever DocuSign returned' do
          subject.send_envelope('foo')
          expect(subject.identifier).to eq 'a-crazy-envelope-id'
        end
      end

      context 'unsuccessful send' do
        let!(:request_stub) { stub_envelope_creation('send_envelope', 'failed_creation', 500) }

        it 'raises a DocusignError with the returned message if not successful' do
          expect {
            subject.send_envelope('foo')
          }.to raise_error(described_class::DocusignError, "Nobody actually loves you; they just pretend until payday.")
        end
      end
    end

    describe '#reload!' do
      it 'reloads status, documents, and recipients from DocuSign' do
        subject.identifier = 'crayons'
        allow(Hancock::DocuSignAdapter).to receive(:new).
          with('crayons').
          and_return(double('adapter', :envelope => {
            'status' => 'bullfree',
            'emailSubject' => 'Subjacked',
            'emailBlurb' => 'Blurble'
          }))
        allow(Hancock::Document).to receive(:fetch_for_envelope).
          with(subject).
          and_return(:le_documeneaux)
        allow(Hancock::Recipient).to receive(:fetch_for_envelope).
          with(subject).
          and_return(:le_recipierre)

        expect(subject.reload!).to eq subject
        expect(subject.status).to eq 'bullfree'
        expect(subject.email).to eq({:subject => 'Subjacked', :blurb => 'Blurble'})
        expect(subject.documents).to eq :le_documeneaux
        expect(subject.recipients).to eq :le_recipierre
      end

      it 'is safe to call even if no identifier' do
        subject.identifier = nil
        expect {
          subject.reload!
        }.not_to raise_error
      end
    end

    describe '.find' do
      it "should find envelope with given ID and #reload! it" do
        envelope = Hancock::Envelope.new(:identifier => 'a-crazy-envelope-id')
        allow(Hancock::DocuSignAdapter).to receive(:new).
          with('a-crazy-envelope-id').
          and_return(double(Hancock::DocuSignAdapter, :envelope => JSON.parse(response_body('envelope'))))

        envelope = double(Hancock::Envelope, :identifier => 'a-crazy-envelope-id')
        allow(described_class).to receive(:new).
          with(:status => 'sent', :identifier => 'a-crazy-envelope-id').
          and_return(envelope)

        expect(envelope).to receive(:reload!).and_return(envelope)
        expect(Hancock::Envelope.find('a-crazy-envelope-id')).to eq envelope
      end
    end

    describe '#add_signature_request' do
      it 'adds a signature request to the envelope, and caches recipients' do
        attributes = {
          :recipient => :a_recipient,
          :document => :a_document,
          :tabs => [:tab1, :tab2]
        }
        subject.add_signature_request(attributes)
        expect(subject.signature_requests).to eq [attributes]
        expect(subject.recipients).to eq [:a_recipient]
      end
    end

    describe '#new' do
      it "can set params on initialization" do
        envelope = Hancock::Envelope.new({
          documents: [:document],
          signature_requests: [:signature_request],
          email: {
            subject: 'Hello there',
            blurb: 'Please sign this!'
          }
        })

        expect(envelope.documents).to eq [:document]
        expect(envelope.signature_requests).to eq [:signature_request]
        expect(envelope.email).to eq({
          subject: 'Hello there',
          blurb: 'Please sign this!'
        })
      end
    end

    describe '#signature_requests_for_params' do
      it 'returns signature requests grouped by recipient and set up for submission' do
        document1 = Hancock::Document.new(:identifier => 1)
        document2 = Hancock::Document.new(:identifier => 2)
        recipient1 = Hancock::Recipient.new(:email => 'b@mail.com', :name => 'Bob', :recipient_type => :signer, :identifier => 1)
        recipient2 = Hancock::Recipient.new(:email => 'e@mail.com', :name => 'Edna', :recipient_type => :signer, :identifier => 2)
        recipient3 = Hancock::Recipient.new(:email => 'f@mail.com', :name => 'Fump', :recipient_type => :editor, :identifier => 3)
        tab1 = double(Hancock::Tab, :type => 'initial_here', :to_h => { :initial => :here })
        tab2 = double(Hancock::Tab, :type => 'sign_here', :to_h => { :sign => :here })
        subject = described_class.new({
          :signature_requests => [
            { :recipient => recipient1, :document => document1, :tabs => [tab1] },
            { :recipient => recipient1, :document => document2, :tabs => [tab1, tab2] },
            { :recipient => recipient2, :document => document1, :tabs => [tab2] },
            { :recipient => recipient2, :document => document2, :tabs => [tab1] },
            { :recipient => recipient3, :document => document2, :tabs => [tab2] },
          ]
        })
        expect(subject.signature_requests_for_params).to eq({
          'signers' => [
            {
              :email => 'b@mail.com', :name => 'Bob', :recipientId => 1, :tabs => {
                :initialHereTabs => [
                  { :initial => :here, :documentId => 1 },
                  { :initial => :here, :documentId => 2 },
                ],
                :signHereTabs => [
                  { :sign => :here, :documentId => 2 },
                ]
              },
            },
            {
              :email => 'e@mail.com', :name => 'Edna', :recipientId => 2, :tabs => {
                :initialHereTabs => [
                  { :initial => :here, :documentId => 2 },
                ],
                :signHereTabs => [
                  { :sign => :here, :documentId => 1 },
                ]
              }
            }
          ],
          'editors' => [
            {
              :email => 'f@mail.com', :name => 'Fump', :recipientId => 3, :tabs => {
                :signHereTabs => [
                  { :sign => :here, :documentId => 2 },
                ]
              }
            }
          ]
        })
      end
    end

    describe '#form_post_body' do
      it 'assembles body for posting' do
        allow(subject).to receive(:email).and_return({ :subject => 'fubject', :blurb => 'flurb'})
        doc1 = double(Hancock::Document, :multipart_form_part => 'Oh my', :to_request => 'horse')
        doc2 = double(Hancock::Document, :multipart_form_part => 'How wondrous', :to_request => 'pony')
        subject.documents = [doc1, doc2]
        allow(subject).to receive(:signature_requests_for_params).
          and_return('the signature requests')
        expect(subject.send(:form_post_body, :a_status)).to eq(
          "\r\n"\
          "--MYBOUNDARY\r\nContent-Type: application/json\r\n"\
          "Content-Disposition: form-data\r\n\r\n"\
          "{\"emailBlurb\":\"flurb\",\"emailSubject\":\"fubject\","\
          "\"status\":\"a_status\",\"documents\":[\"horse\",\"pony\"],"\
          "\"recipients\":\"the signature requests\"}\r\n"\
          "--MYBOUNDARY\r\nOh my\r\n"\
          "--MYBOUNDARY\r\nHow wondrous\r\n"\
          "--MYBOUNDARY--\r\n"
        )
      end
    end
  end
end
