require_relative "contract"

module JobContracts
  class DurationContract < Contract
    def initialize(duration:)
      super
    end

    def enforce!(contractable)
      actual[:duration] = (Time.current - Time.parse(contractable.enqueued_at)).seconds
      self.satisfied = actual[:duration] < expect[:duration].seconds
      super
    end
  end
end
