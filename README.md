* Title: drphil.rb - Voting Bot
* Tags: radiator ruby steem howto curation
* Notes: 

Dr. Phil (`drphil.rb`) is reimplementation of the "Winfrey" voting bot specification.  The goal is to give everyone an upvote.

One optional improvement is that instead of voting 1% by 100 accounts like the Winfrey bot spec, this script can vote 100% with 1 randomly chosen account.

If the complaint about Winfrey is blockchain bloat, Dr. Phil prescribes weight loss to address this. But this feature would only work if there are enough voters defined in the script.  If you plan to use this script for one or two accounts, you'll probably want to adjust the `VOTE_WEIGHT` constant to something a bit lower.

---

To use this [Radiator](https://steemit.com/steem/@inertia/radiator-steem-ruby-api-client) bot:

##### Linux

```bash
$ sudo apt-get install ruby-full git openssl libssl1.0.0 libssl-dev
$ gem install bundler
```

##### macOS

```bash
$ gem install bundler
```

I've tested it on various versions of ruby.  The oldest one I got it to work was:

`ruby 2.0.0p645 (2015-04-13 revision 50299) [x86_64-darwin14.4.0]`

First, make a project folder:

```bash
$ mkdir radiator
$ cd radiator
```

Create a file named `Gemfile` containing:

```ruby
source 'https://rubygems.org'
gem 'radiator', git: 'git@github.com:inertia186/radiator.git'
```

Then run the command:

```bash
$ bundle install
```

Create a file named `drphil.rb` containing:

```ruby
require 'rubygems'
require 'bundler/setup'

Bundler.require

# If there are problems, this is the most time we'll wait (in seconds).
MAX_BACKOFF = 12.8
VOTE_WEIGHT = "100.00 %"
WAIT_RANGE = [1..3]

@voters = %w(
  social 5JrvPrQeBBvCRdjv29iDvkwn3EQYZ9jqfAHzrCyUvfbEbRkrYFC
  bad.account 5XXXBadWifXXXdjv29iDvkwn3EQYZ9jqfAHzrCyUvfbEbRkrYFC
).each_slice(2).to_h

@skip_accounts = %w(
  leeroy.jenkins the.masses danlarimer ned-reddit-login
)

@skip_tags = %w(
  nsfw test
)

@flag_signals = %w(
  cheetah steemcleaners
)

@options = {
  chain: :steem,
  url: 'https://steemd.steemit.com',
  logger: Logger.new(__FILE__.sub(/\.rb$/, '.log'))
}

@api = Radiator::Api.new(@options)
@stream = Radiator::Stream.new(@options)

def may_vote?(comment)
  return false unless comment.depth == 0
  return false if (@skip_tags & JSON[comment.json_metadata]['tags']).any?
  return false if @skip_accounts.include? comment.author
  
  true
end

def vote(comment)
  backoff = 0.2
  voters = @voters.keys
  response = @api.get_content(comment.author, comment.permlink)
  comment = response.result
  
  Thread.new do
    wait = Random.rand(*WAIT_RANGE) * 60
    sleep wait
    
    loop do
      begin
        break if voters.empty?
        
        author = comment.author
        permlink = comment.permlink
        voter = voters.sample
        
        all_voters = comment.active_votes.map(&:voter)
        downvoters = comment.active_votes.map do |v|
          v.voter if v.percent < 0
        end.compact
        
        if comment.author_reputation.to_i < 0
          break
        end
        
        if (downvoters & @flag_signals).any?
          break
        end
        
        if all_voters.include? voter
          voters -= [voter]
          next
        end
        
        wif = @voters[voter]
        tx = Radiator::Transaction.new(@options.merge(wif: wif))
        
        puts "#{voter} voting for @#{author}/#{permlink}"
        
        vote = {
          type: :vote,
          voter: voter,
          author: author,
          permlink: permlink,
          weight: (VOTE_WEIGHT.to_f * 100).to_i
        }
        
        op = Radiator::Operation.new(vote)
        tx.operations << op
        response = tx.process(true)
        
        if !!response.error
          message = response.error.message
          if message.to_s =~ /You have already voted in a similar way./
            voters -= [voter]
            next
          elsif message.to_s =~ /Can only vote once every 3 seconds./
            voters -= [voter]
            next
          end
          raise message
        end
        
        puts "\tSuccess: #{response.result.to_json}"
        
        break
      rescue => e
        puts "Pausing #{backoff} :: Unable to vote with #{voter}.  #{e}"
        voters -= [voter]
        sleep backoff
        backoff = [backoff * 2, MAX_BACKOFF].min
      end
    end
  end
end

@stream.operations(:comment) do |comment|
  next unless may_vote? comment
  
  vote(comment)
end
```

Then run it:

```bash
$ ruby drphil.rb
```

Dr. Phil will now do it's thing.  Check here to see an updated version of this bot:

https://gist.github.com/inertia186/61bcc2b821aa5acb24f7fc88921950c7

<center>
  ![](https://cl.ly/1j1Z262a2A3d/Image%202017-03-22%20at%2012.17.22%20PM.png)
</center>

See my previous Ruby How To posts in: [#radiator](https://steemit.com/created/radiator) [#ruby](https://steemit.com/created/ruby)

