require "digest"

module Candidates
  class ResumeStorage
    class InvalidUpload < StandardError; end

    MAX_BYTES = 10.megabytes
    CONTENT_TYPES = {
      ".pdf" => "application/pdf",
      ".doc" => "application/msword",
      ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ".txt" => "text/plain"
    }.freeze

    def initialize(actor)
      @actor = actor
    end

    def upload(candidate, upload)
      Access.new(@actor).authorize_update!(candidate)
      unless upload.is_a?(ActionDispatch::Http::UploadedFile)
        raise InvalidUpload, "file must be a multipart upload"
      end
      raise InvalidUpload, "file must contain 1 to #{MAX_BYTES} bytes" unless upload.size.between?(1, MAX_BYTES)

      filename = ActiveStorage::Filename.new(upload.original_filename).sanitized
      content_type = CONTENT_TYPES[File.extname(filename).downcase]
      upload.rewind
      detected_type = Marcel::MimeType.for(upload.tempfile)
      upload.rewind
      bytes = upload.read(MAX_BYTES + 1)
      upload.rewind
      raise InvalidUpload, "file is too large" if bytes.bytesize > MAX_BYTES
      if content_type == "text/plain"
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        valid_text = text.valid_encoding? && !text.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f]/)
        detected_type = "text/plain" if valid_text && detected_type == "application/octet-stream"
        raise InvalidUpload, "invalid text document" unless valid_text
      end
      unless content_type && detected_type == content_type
        raise InvalidUpload, "unsupported document type or filename mismatch"
      end

      digest = Digest::SHA256.hexdigest(bytes)
      blob = nil
      candidate.with_lock(requires_new: true) do
        Access.new(@actor).authorize_update!(candidate)
        existing = CandidateResume.find_by(candidate: candidate, sha256: digest)
        return [ existing, false ] if existing

        blob = ActiveStorage::Blob.build_after_unfurling(io: upload.tempfile, filename: filename,
          content_type: content_type, identify: false, metadata: { analyzed: true })
        blob.save!
        blob.upload_without_unfurling(upload.tempfile)
        resume = CandidateResume.new(candidate: candidate, uploaded_by: @actor, sha256: digest)
        resume.original = blob
        resume.save!
        AuditEvent.record!(actor: @actor, action: "candidate.resume_uploaded", subject: resume)
        [ resume, true ]
      end
    rescue StandardError
      # A rollback removes database rows but does not remove bytes already uploaded.
      blob.service.delete(blob.key) if blob && !ActiveStorage::Blob.exists?(id: blob.id)
      raise
    end
  end
end
