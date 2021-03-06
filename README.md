[![Lines of Code](http://img.shields.io/badge/lines_of_code-236-brightgreen.svg?style=flat)](http://blog.codinghorror.com/the-best-code-is-no-code-at-all/)
[![Code Quality](https://app.codacy.com/project/badge/Grade/f604d4bc6db0474c802ef51182732488)](https://www.codacy.com/gh/hopsoft/job_contracts/dashboard?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=hopsoft/job_contracts&amp;utm_campaign=Badge_Grade)
[![Tests](https://github.com/hopsoft/job_contracts/actions/workflows/test.yml/badge.svg)](https://github.com/orbit-love/job_contracts/actions/workflows/test.yml)
[![Gem Version](https://badge.fury.io/rb/job_contracts.svg)](https://badge.fury.io/rb/job_contracts)
[![Gem Downloads](https://img.shields.io/gem/dt/job_contracts)](https://rubygems.org/gems/job_contracts)

# Job Contracts

## Test-like assurances for jobs

Have you ever wanted to prevent a background job from writing to the database or perhaps ensure that it completes within a fixed amount of time?

Contracts allow you to easily enforce guarantees like this.

<!-- Tocer[start]: Auto-generated, don't remove. -->

## Table of Contents

  - [Why use Contracts?](#why-use-contracts)
  - [Quick Start](#quick-start)
  - [Contracts](#contracts)
    - [Breach of Contract](#breach-of-contract)
    - [Anatomy of a Contract](#anatomy-of-a-contract)
    - [Defining a Contract](#defining-a-contract)
    - [Using a Contract](#using-a-contract)
  - [Worker Formation/Topology](#worker-formationtopology)
  - [Advanced Usage](#advanced-usage)
  - [Sidekiq](#sidekiq)
  - [Todo](#todo)
  - [License](#license)
  - [Sponsors](#sponsors)

<!-- Tocer[finish]: Auto-generated, don't remove. -->

## Why use Contracts?

- Organize your code for better reuse, consistency, and maintainability
- Refine your telemetry and instrumentation efforts
- Improve job performance via enforced *(SLAs/SLOs/SLIs)*
- Monitor and manage job queue backpressure
- Improve your worker formation/topology to support high throughput

## Quick Start

Imagine you want to ensure a specific job completes within 5 seconds of being enqueued.

```ruby
class ImportantJob < ApplicationJob
  include JobContracts::Contractable

  queue_as :default
  add_contract JobContracts::DurationContract.new(max: 5.seconds)

  def perform
    # logic...
  end

  # default callback that's invoked if the contract is breached
  def contract_breached!(contract)
    # handle breach...
  end
end
```

*How to handle a [__breach of contract__](#breach-of-contract).*

## Contracts

A contract is an agreement that a job should fulfill.
Failing to satisfy the contract is considered a __breach of contract__.

Contracts help you track `actual` results and compare them to `expected` outcomes.
For example, this project has a default set of contracts that verify the following:

- That a job will [execute within a set amount of time](https://github.com/hopsoft/job_contracts/blob/main/lib/job_contracts/contracts/duration_contract.rb)
- That a job is only [performed on a specific queue](https://github.com/hopsoft/job_contracts/blob/main/lib/job_contracts/contracts/queue_name_contract.rb)
- That a job [does not write to the database](https://github.com/hopsoft/job_contracts/blob/main/lib/job_contracts/contracts/read_only_contract.rb)

### Breach of Contract

A __breach of contract__ is similar to a test failure; however, the breach can be handled in many different ways.

- Log and instrument the breach and continue
- Halt processing of the job and all other contracts and raise an exception
- Move the job to a queue where the contract will not be enforced
- etc...

*Mix and match any combination of these options to support your requirements.*

### Anatomy of a Contract

Contracts support the following constructor arguments.

- __`trigger`__ `[Symbol] (:before, *:after)` - when contract enforcement takes place, *before or after perform*
- __`halt`__ `[Boolean] (true, *false)` - indicates whether or not to stop processing when the contract is breached
- __`queues`__ `[Array<String,Symbol>]` - a list of queue names where this contract will be enforced _(defaults to the configured queue, or `*` if the queue has not beeen configured)_
- __`expected`__ `[Hash]` - a dictionary of contract expectations

### Defining a Contract

Here's a contrived, but simple, example that ensures the first argument passed to perform fits within a specific range of values.

```ruby
# app/contracts/argument_contract.rb
class ArgumentContract < JobContracts::Contract
  def initialize(range:)
    # enforced on all queues
    super queues: ["*"], expected: {range: range}
  end

  def enforce!(contractable)
    actual[:argument] = contractable.arguments.first
    self.satisfied = expected[:range].cover?(actual[:argument])
    super
  end
end
```

### Using a Contract

Here's how to use the `ArgumentContract` in a job.

```ruby
# app/jobs/argument_example_job.rb
class ArgumentExampleJob < ApplicationJob
  include JobContracts::Contractable

  queue_as :default
  add_contract ArgumentContract.new(range: (1..10))

  def perform(arg)
    # logic...
  end

  # default callback that's invoked if the contract is breached
  def contract_breached!(contract)
    # handle breach...
  end
end
```

This job will help ensure that the argument passed to perform is between 1 and 10.
*It's up to you to determine how to handle a breach of contract.*

## Worker Formation/Topology

Thoughtful Rails applications often use specialized worker formations.

A simple formation might be to use two sets of workers.
One set dedicated to fast low-latency jobs with plenty of dedicated compute resources *(CPUs, processes, threads, etc...)*,
with another set dedicated to slower jobs that uses fewer compute resources.

<img width="593" alt="Untitled 2 2022-04-29 15-06-13" src="https://user-images.githubusercontent.com/32920/166069103-e316dcc7-e601-43d0-90df-ad0eda20409b.png">

Say we determine that fast low-latency jobs should __not__ write to the database.

We can use a [`ReadOnlyContract`](https://github.com/hopsoft/job_contracts/blob/main/lib/job_contracts/contracts/read_only_contract.rb)
to enforce this decision. If the contract is breached, we can notify our apm/monitoring service and re-enqueue the job to a slower queue *(worker set)* where database writes are permitted.
This will ensure that our fast low-latency queue doesn't get clogged with slow-running jobs.

Here's an example job implementation that accomplishes this.

```ruby
class FastJob < ApplicationJob
  include JobContracts::Contractable

  # Configure the queue before adding contracts
  # It will be used as the default enforcement queue for contracts
  queue_as :critical

  # Only enforces on the critical queue
  # This allows us to halt job execution and reenqueue the job to a different queue
  # where the contract will not be enforced
  #
  # NOTE: the arg `queues: [:critical]` is default behavior in this example
  #       we're setting it explicitly here for illustration purposes
  add_contract JobContracts::ReadOnlyContract.new(queues: [:critical])

  def perform
    # logic that shouldn't write to the database,
    # but might accidentally due to complex or opaque internals
  end

  def contract_breached!(contract)
    # log and notify apm/monitoring service

    # re-enqueue to a different queue
    # where the database write will be permitted
    # i.e. where the contract will not be enforced
    enqueue queue: :default
  end
end
```

*Worker formations can be designed in countless ways to handle incredibly sophisticated requirements and operational constraints.
The only real limitation is your creativity.*

## Advanced Usage

It's possible to override the default callback method that handles contract breaches.

```ruby
class ImportantJob < ApplicationJob
  include JobContracts::Contractable

  queue_as :default
  on_contract_breach :take_action
  add_contract JobContracts::DurationContract.new(max: 5.seconds)

  def perform
    # logic...
  end

  def take_action(contract)
    # handle breach...
  end
end
```

```ruby
class ImportantJob < ApplicationJob
  include JobContracts::Contractable

  queue_as :default
  on_contract_breach -> (contract) { # take action... }

  add_contract JobContracts::DurationContract.new(max: 5.seconds)

  def perform
    # logic...
  end
end
```

## Sidekiq

`Sidekiq::Job`s are also supported.

```ruby
class ImportantJob
  include Sidekiq::Job
  include JobContracts::SidekiqContractable

  sidekiq_options queue: :default
  add_contract JobContracts::DurationContract.new(max: 1.second)

  def perform
    # logic...
  end

  # default callback that's invoked if the contract is breached
  def contract_breached!(contract)
    # handle breach...
  end
end
```

## Todo

- [ ] Sidekiq tests

## License

The gem is available as open-source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Sponsors

This project is sponsored by [Orbit.love](https://orbit.love/?utm_source=github&utm_medium=repo&utm_campaign=hopsoft&utm_content=job_contracts) *(mission control for your community)*.

<a href="https://orbit.love/?utm_source=github&utm_medium=repo&utm_campaign=hopsoft&utm_content=job_contracts">
  <img height="50" src="https://user-images.githubusercontent.com/32920/166343064-55f92cdb-c81b-4f85-80a8-167bfda73c85.png"></img>
</a>

---

This effort was partly inspired by a presentation at [Sin City Ruby](https://www.sincityruby.com/) from our friends on the platform team at [Gusto](https://gusto.com/).
Their presentation validated some of my prior solutions aimed at accomplishing similar goals and motivated me to extract that work into a GEM.
