module ImmutableVersion
  extend ActiveSupport::Concern

  def readonly?
    persisted?
  end
end
