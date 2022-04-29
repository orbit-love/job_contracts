# frozen_string_literal: true

class MultipleContractsExampleJob < ApplicationJob
  include JobContracts::Contractable

  queue_as :low

  add_contract JobContracts::QueueNameContract.new(queue_name: :low)
  add_contract JobContracts::DurationContract.new(duration: 1.second)
  add_contract JobContracts::ReadOnlyContract.new

  after_contract_breach :contract_breached

  def perform
    sleep 2
    User.create! name: "test"
  end

  private

  def contract_breached(contract)
    # TODO: notify error monitoring service
    Rails.logger.info "Contract violation! #{contract.inspect}"

    # re-enqueue to the queue expected by the queue name contract
    enqueue queue: contract.expect[:queue_name] if contract.is_a?(JobContracts::QueueNameContract)
  end
end