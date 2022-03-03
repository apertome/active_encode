# frozen_string_literal: true
require 'rails_helper'
require 'active_encode/spec/shared_specs'

# example s3 url TODO: remove
# s3://masterfiles/uploads/5cb6b01c-95c9-4621-ac83-bbdaa8450078/Secrets of Binary Code.mp4

describe ActiveEncode::EngineAdapters::FfmpegAdapter do
  around do |example|
    ActiveEncode::Base.engine_adapter = :ffmpeg

    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
      Dir.foreach(dir) do |e|
        next if e == "." || e == ".."
        FileUtils.rm_rf(File.join(dir, e))
      end
    end

    ActiveEncode::Base.engine_adapter = :test
  end

  let!(:work_dir) { stub_const "ActiveEncode::EngineAdapters::FfmpegAdapter::WORK_DIR", @dir }
  let(:file) { "file://" + Rails.root.join('..', 'spec', 'fixtures', 'fireworks.mp4').to_s }
  let(:created_job) do
    #  puts "created_job file: #{file}"
    ActiveEncode::Base.create(file, outputs: [{ label: "low", ffmpeg_opt: "-s 640x480", extension: "mp4" }, { label: "high", ffmpeg_opt: "-s 1280x720", extension: "mp4" }])
  end
  let(:running_job) do
    allow(Process).to receive(:getpgid).and_return 8888
    find_encode "running-id"
  end
  let(:canceled_job) do
    find_encode 'cancelled-id'
  end
  let(:cancelling_job) do
    allow(Process).to receive(:kill).and_return(nil)
    encode = find_encode 'running-id'
    File.write "#{work_dir}/running-id/cancelled", ""
    encode
  end
  let(:completed_job) { find_encode "completed-id" }
  let(:failed_job) { find_encode 'failed-id' }
  let(:completed_tech_metadata) do
    {
      audio_bitrate: 171_030,
      audio_codec: 'mp4a-40-2',
      duration: 6315,
      file_size: 199_160,
      frame_rate: 23.719,
      height: 110.0,
      id: "99999",
      url: "/home/pdinh/Downloads/videoshort.mp4",
      video_bitrate: 74_477,
      video_codec: 'avc1',
      width: 200.0
    }
  end
  let(:completed_output) { [{ id: "99999" }] }
  let(:failed_tech_metadata) { {} }

  it_behaves_like "an ActiveEncode::EngineAdapter"

  def find_encode(id)
    # Precreate ffmpeg output directory and files
    FileUtils.copy_entry "spec/fixtures/ffmpeg/#{id}", "#{work_dir}/#{id}"

    # Simulate that progress is modified later than other files
    sleep 0.1
    FileUtils.touch "#{work_dir}/#{id}/progress"
    FileUtils.touch Dir.glob("#{work_dir}/#{id}/*.mp4")

    # Stub out system calls
    allow_any_instance_of(ActiveEncode::EngineAdapters::FfmpegAdapter).to receive(:`).and_return(1234)

    ActiveEncode::Base.find(id)
  end

  describe "#create" do
    subject { created_job }

    it "creates a directory whose name is the encode id" do
      expect(File).to exist("#{work_dir}/#{subject.id}")
    end

    context "input file exists" do
      it "has the input technical metadata in a file" do
        expect(File.read("#{work_dir}/#{subject.id}/input_metadata")).not_to be_empty
      end

      it "has the pid in a file" do
        expect(File.read("#{work_dir}/#{subject.id}/pid")).not_to be_empty
      end
    end

    context "input file doesn't exist" do
      let(:missing_file) { "file:///a_bogus_file.mp4" }
      let(:missing_job) { ActiveEncode::Base.create(missing_file, outputs: [{ label: "low", ffmpeg_opt: "-s 640x480", extension: 'mp4' }]) }

      it "returns the encode with correct error" do
        expect(missing_job.errors).to include("#{missing_file} does not exist or is not accessible")
        expect(missing_job.percent_complete).to be 1
        # expect(missing_job.exit_status).not_to be 0
      end
    end

    context "input file is not media" do
      let(:nonmedia_file) { "file://" + Rails.root.join('Gemfile').to_s }
      let(:nonmedia_job) { ActiveEncode::Base.create(nonmedia_file, outputs: [{ label: "low", ffmpeg_opt: "-s 640x480", extension: 'mp4' }]) }

      it "returns the encode with correct error" do
        expect(nonmedia_job.errors).to include("Error inspecting input: #{nonmedia_file}")
        expect(nonmedia_job.percent_complete).to be 1
        # expect(missing_job.exit_status).not_to be 0
      end
    end

    context "input filename with spaces" do
      let(:file_with_space) { "file://" + Rails.root.join('..', 'spec', 'fixtures', 'file with space.mp4').to_s }
      let!(:create_space_job) { ActiveEncode::Base.create(file_with_space, outputs: [{ label: "low", ffmpeg_opt: "-s 640x480", extension: 'mp4' }]) }
      let(:find_space_job) { ActiveEncode::Base.find create_space_job.id }

      it "does not have errors" do
        sleep 2
        expect(find_space_job.errors).to be_empty
        # expect(find_space_job.exit_status).to be 0
      end

      it "has the input technical metadata in a file" do
        expect(File.read("#{work_dir}/#{create_space_job.id}/input_metadata")).not_to be_empty
      end

      it "has the pid in a file" do
        expect(File.read("#{work_dir}/#{create_space_job.id}/pid")).not_to be_empty
      end

      context 'when uri encoded' do
        let(:file_with_space) { Addressable::URI.encode("file://" + Rails.root.join('..', 'spec', 'fixtures', 'file with space.mp4').to_s) }

        it "does not have errors" do
          sleep 2
          expect(find_space_job.errors).to be_empty
        end

        it "has the input technical metadata in a file" do
          expect(File.read("#{work_dir}/#{create_space_job.id}/input_metadata")).not_to be_empty
        end

        it "has the pid in a file" do
          expect(File.read("#{work_dir}/#{create_space_job.id}/pid")).not_to be_empty
        end
      end
    end

    # let(:s3_file) { "s3://hostname/uploads/some_id/fireworks space.mp4" }
    # let(:s3_file_with_spaces) { "s3://hostname/uploads/some_id/file with space.mp4" }
    # context "input s3 uri" do
    #   # let(:file_with_space) { "file://" + Rails.root.join('..', 'spec', 'fixtures', 'file with space.mp4').to_s }
    #   let!(:create_space_job) { ActiveEncode::Base.create(s3_file, outputs: [{ label: "low", ffmpeg_opt: "-s 640x480", extension: 'mp4' }]) }
    #   let(:find_space_job) { ActiveEncode::Base.find create_space_job.id }
    #
    #   it "does not have errors" do
    #     sleep 2
    #     puts "s3 file found"
    #     pp find_space_job
    #     expect(find_space_job.errors).to be_empty
    #     # expect(find_space_job.exit_status).to be 0
    #   end
    #
    #   it "has the input technical metadata in a file" do
    #     expect(File.read("#{work_dir}/#{create_space_job.id}/input_metadata")).not_to be_empty
    #   end
    #
    #   it "has the pid in a file" do
    #     expect(File.read("#{work_dir}/#{create_space_job.id}/pid")).not_to be_empty
    #   end
    #
    #   context 'when uri encoded' do
    #     let(:s3_file) { Addressable::URI.encode( "s3://hostname/uploads/some_id/fireworks.mp4" ) }
    #
    #     it "does not have errors" do
    #       sleep 2
    #       expect(find_space_job.errors).to be_empty
    #     end
    #
    #     it "has the input technical metadata in a file" do
    #       expect(File.read("#{work_dir}/#{create_space_job.id}/input_metadata")).not_to be_empty
    #     end
    #
    #     it "has the pid in a file" do
    #       expect(File.read("#{work_dir}/#{create_space_job.id}/pid")).not_to be_empty
    #     end
    #   end
    # end



    context 'when failed' do
      subject { created_job }

      before do
        allow_any_instance_of(Object).to receive(:`).and_raise Errno::ENOENT
      end

      it { is_expected.to be_failed }
      it { expect(subject.errors).to be_present }
    end
  end

  describe "#find" do
    subject { running_job }

    it "has a progress file" do
      expect(File).to exist("#{work_dir}/#{subject.id}/progress")
    end
  end

  describe "#cancel!" do
    subject { running_job }

    it "stops a running process" do
      expect(Process).to receive(:kill).with('SIGTERM', running_job.input.id.to_i)
      running_job.cancel!
    end

    it "does not attempt to stop a non-running encode" do
      expect(Process).not_to receive(:kill).with('SIGTERM', completed_job.input.id.to_i)
      completed_job.cancel!
    end

    it "raises an error if the process can not be found" do
      expect(Process).to receive(:kill).with('SIGTERM', running_job.input.id.to_i).and_raise(Errno::ESRCH)
      expect { running_job.cancel! }.to raise_error(ActiveEncode::NotRunningError)
    end

    it "raises an error" do
      expect(Process).to receive(:kill).with('SIGTERM', running_job.input.id.to_i).and_raise(Errno::EPERM)
      expect { running_job.cancel! }.to raise_error(ActiveEncode::CancelError)
    end
  end
end
