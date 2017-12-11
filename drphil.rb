# Dr. Phil (drphil) is reimplmentation of the winfrey voting bot.  The goal is
# to give everyone an upvote.  But instead of voting 1% by 100 accounts like
# winfrey, this script will vote 100% with 1 randomly chosen account.
#
# See: https://steemit.com/radiator/@inertia/drphil-rb-voting-bot

require 'rubygems'
require 'bundler/setup'
require 'yaml'

Bundler.require

# If there are problems, this is the most time we'll wait (in seconds).
MAX_BACKOFF = 12.8

VOTE_RECHARGE_PER_DAY = 20.0
VOTE_RECHARGE_PER_HOUR = VOTE_RECHARGE_PER_DAY / 24
VOTE_RECHARGE_PER_MINUTE = VOTE_RECHARGE_PER_HOUR / 60
VOTE_RECHARGE_PER_SEC = VOTE_RECHARGE_PER_MINUTE / 60

@config_path = __FILE__.sub(/\.rb$/, '.yml')

unless File.exist? @config_path
  puts "Unable to find: #{@config_path}"
  exit
end

def parse_voters(voters)
  case voters
  when String
    raise "Not found: #{voters}" unless File.exist? voters

    f = File.open(voters)
    hash = {}
    f.read.each_line do |pair|
      key, value = pair.split(' ')
      hash[key] = value if !!key && !!hash
    end

    hash
  when Array
    a = voters.map{ |v| v.split(' ')}.flatten.each_slice(2)

    return a.to_h if a.respond_to? :to_h

    hash = {}

    voters.each_with_index do |e|
      key, val = e.split(' ')
      hash[key] = val
    end

    hash
  else; raise "Unsupported voters: #{voters}"
  end
end

def parse_list(list)
  if !!list && File.exist?(list)
    f = File.open(list)
    elements = []

    f.each_line do |line|
      elements += line.split(' ')
    end

    elements.uniq.reject(&:empty?).reject(&:nil?)
  else
    list.to_s.split(' ')
  end
end

@config = YAML.load_file(@config_path)
rules = @config['voting_rules']

@voting_rules = {
  mode: rules['mode'] || 'drphil',
  vote_weight: (((rules['vote_weight'] || '100.0 %').to_f) * 100).to_i,
  favorites_vote_weight: (((rules['favorites_vote_weight'] || rules['vote_weight'] || '100.0 %').to_f) * 100).to_i,
  following_vote_weight: (((rules['following_vote_weight'] || rules['vote_weight'] || '100.0 %').to_f) * 100).to_i,
  followers_vote_weight: (((rules['followers_vote_weight'] || rules['vote_weight'] || '100.0 %').to_f) * 100).to_i,
  enable_comments: rules['enable_comments'],
  only_first_posts: rules['only_first_posts'],
  only_fully_powered_up: rules['only_fully_powered_up'],
  min_wait: rules['min_wait'].to_i,
  max_wait: rules['max_wait'].to_i,
  min_rep: (rules['min_rep'] || 25.0),
  max_rep: (rules['max_rep'] || 99.9).to_f,
  min_voting_power: (((rules['min_voting_power'] || '0.0 %').to_f) * 100).to_i,
  unique_author: rules['unique_author'],
  max_votes_per_post: rules['max_votes_per_post'],
}

@voting_rules[:wait_range] = [@voting_rules[:min_wait]..@voting_rules[:max_wait]]

unless @voting_rules[:min_rep] =~ /dynamic:[0-9]+/
  @voting_rules[:min_rep] = @voting_rules[:min_rep].to_f
end

@voting_rules = Struct.new(*@voting_rules.keys).new(*@voting_rules.values)

@voters = parse_voters(@config['voters'])
@favorite_accounts = parse_list(@config['favorite_accounts'])
@skip_accounts = parse_list(@config['skip_accounts'])
@skip_tags = parse_list(@config['skip_tags'])
@only_tags = parse_list(@config['only_tags'])
@skip_apps = parse_list(@config['skip_apps'])
@only_apps = parse_list(@config['only_apps'])
@flag_signals = parse_list(@config['flag_signals'])
@vote_signals = parse_list(@config['vote_signals'])

@favorite_account_weights = @favorite_accounts.map do |account|
  pair = account.split(':')
  next unless pair.size == 2

  pair[1] = (pair[1].to_f * 100).to_i
  pair
end.compact.to_h

@favorite_accounts = @favorite_accounts.map do |account|
  account.split(':').first
end

@chain_options = @config[:chain_options]
@chain_options[:chain] = @chain_options[:chain].to_sym
@chain_options[:logger] = Logger.new(__FILE__.sub(/\.rb$/, '.log'))

def winfrey?; @voting_rules.mode == 'winfrey'; end
def drphil?; @voting_rules.mode == 'drphil'; end
def seinfeld?; @voting_rules.mode == 'seinfeld'; end

if (
    !seinfeld? &&
    @voting_rules.vote_weight == 0 && @voting_rules.favorites_vote_weight == 0 &&
    @voting_rules.following_vote_weight == 0 && @voting_rules.followers_vote_weight == 0
  )
  puts "WARNING: All vote weights are zero.  This is a bot that does nothing."
  @voting_rules.mode = 'seinfeld'
end

@voted_for_authors = {}
@voting_power = {}
@threads = {}
@semaphore = Mutex.new

def to_rep(raw)
  raw = raw.to_i
  neg = raw < 0
  level = Math.log10(raw.abs)
  level = [level - 9, 0].max
  level = (neg ? -1 : 1) * level
  level = (level * 9) + 25

  level
end

def poll_voting_power
  @semaphore.synchronize do
    @api.get_accounts(@voters.keys) do |accounts, error|
      if !!error
        puts "Unable to query voters #{@voters.keys.join(', ')}: #{error}"
        return
      end
      
      accounts.each do |account|
        voting_power = account.voting_power / 100.0
        last_vote_time = Time.parse(account.last_vote_time + 'Z')
        voting_elapse = Time.now.utc - last_vote_time
        current_voting_power = voting_power + (voting_elapse * VOTE_RECHARGE_PER_SEC)
        wasted_voting_power = [current_voting_power - 100.0, 0.0].max
        current_voting_power = ([100.0, current_voting_power].min * 100).to_i
        
        if wasted_voting_power > 0
          puts "\t#{account.name} wasted voting power: #{('%.2f' % wasted_voting_power)} %"
        end
        
        @voting_power[account.name] = current_voting_power
      end
      
      @min_voting_power = @voting_power.values.min
      @max_voting_power = @voting_power.values.max
      @average_voting_power = @voting_power.values.reduce(0, :+) / accounts.size
    end
  end
end

def summary_voting_power
  poll_voting_power
  vp = @average_voting_power / 100.0
  summary = []

  summary << if @voting_power.size > 1
    "Average remaining voting power: #{('%.3f' % vp)} %"
  else
    "Remaining voting power: #{('%.3f' % vp)} %"
  end

  if @voting_power.size > 1 && @max_voting_power > @voting_rules.min_voting_power
    vp = @max_voting_power / 100.0

    summary << "highest account: #{('%.3f' % vp)} %"
  end

  vp = @voting_rules.min_voting_power / 100.0
  summary << "recharging when below: #{('%.3f' % vp)} %"

  summary.join('; ')
end

def voters_recharging
  @voting_power.map do |voter, power|
    voter if power < @voting_rules.min_voting_power
  end.compact
end

def skip_tags_intersection?(json_metadata)
  metadata = JSON[json_metadata || '{}'] rescue {}
  tags = metadata['tags'] || [] rescue []
  tags = [tags].flatten

  (@skip_tags & tags).any?
end

def only_tags_intersection?(json_metadata)
  return true if @only_tags.none? # not set, assume all tags intersect

  metadata = JSON[json_metadata || '{}'] rescue {}
  tags = metadata['tags'] || [] rescue []
  tags = [tags].flatten

  (@only_tags & tags).any?
end

def skip_app?(json_metadata)
  metadata = JSON[json_metadata || '{}'] rescue {}
  app = metadata['app'].to_s.split('/').first

  @skip_apps.include? app
end

def only_app?(json_metadata)
  return true if @only_apps.none?

  metadata = JSON[json_metadata || '{}'] rescue {}
  app = metadata['app'].to_s.split('/').first

  @only_apps.include? app
end

def voted_for_authors
  limit = if @voted_for_authors.empty?
    10000
  else
    300
  end

  @semaphore.synchronize do
    @voters.keys.each do |voter|
      @api.get_account_history(voter, -limit, limit) do |result, error|
        if !!error
          puts "Unable to get account hitory for #{voter}: #{error}"
          next
        end
        
        result.reverse.each do |i, tx|
          op = tx['op']
          next unless op[0] == 'vote'

          timestamp = Time.parse(tx['timestamp'] + 'Z')
          latest = @voted_for_authors[op[1]['author']]

          if latest.nil? || latest < timestamp
            @voted_for_authors[op[1]['author']] = timestamp
          end
        end
      end
    end
  end

  @voted_for_authors
end

def already_voted_for?(author, unique_author = @voting_rules.unique_author)
  return false if unique_author.nil?

  now = Time.now.utc
  voted_in_threshold = []

  voted_for_authors.each do |author, vote_at|
    if now - vote_at < unique_author * 60
      voted_in_threshold << author
    end
  end

  return true if voted_in_threshold.include? author

  false
end

def may_vote?(comment)
  return false if !@voting_rules.enable_comments && !comment.parent_author.empty?
  return false if @skip_tags.include? comment.parent_permlink
  return false if skip_tags_intersection? comment.json_metadata
  return false unless only_tags_intersection? comment.json_metadata
  return false if @skip_accounts.include? comment.author
  return false if skip_app? comment.json_metadata
  return false unless only_app? comment.json_metadata

  # We are checking if any voter can vote at all.  If at least one voter has a
  # non-zero vote_weight, return true.  Otherwise, don't bother to even queue up
  # a thread.
  if @voters.keys.map { |voter| vote_weight(comment.author, voter) > 0.0 }.include? true
    true
  else
    false
  end
end

def min_trending_rep(limit)
  begin
    @semaphore.synchronize do
      if @min_trending_rep.nil? || Random.rand(0..limit) == 13
        puts "Looking up trending up to #{limit} posts."

        @api.get_discussions_by_trending(tag: '', limit: limit) do |trending, error|
          raise error.message if !!error

          @min_trending_rep = trending.map do |c|
            c.author_reputation.to_i
          end.min
  
          puts "Current minimum dynamic rep: #{('%.3f' % to_rep(@min_trending_rep))}"
        end
      end
    end
  rescue => e
    puts "Warning: #{e}"
  end

  @min_trending_rep || 0
end

def skip?(comment, voters)
  if comment.respond_to? :cashout_time # HF18
    if (cashout_time = Time.parse(comment.cashout_time + 'Z')) < Time.now.utc
      puts "Skipped, cashout time has passed (#{cashout_time}):\n\t@#{comment.author}/#{comment.permlink}"
      return true
    end
  end

  if !!@voting_rules.only_first_posts
    begin
      @semaphore.synchronize do
        @api.get_accounts([comment.author]) do |account, error|
          if !!error
            puts "Unable to find first post for #{comment.author}: #{error}"
            return true
          end

          if account.post_count > 1
            puts "Skipped, not first post:\n\t@#{comment.author}/#{comment.permlink}"
            return true
          end
        end
      end
    rescue => e
      puts "Warning: #{e}"
      return true
    end
  end

  if !!@voting_rules.only_fully_powered_up
    unless comment.percent_steem_dollars == 0
      puts "Skipped, reward not fully powered up:\n\t@#{comment.author}/#{comment.permlink}"
      return true
    end
  end

  if comment.max_accepted_payout.split(' ').first == '0.000'
    puts "Skipped, payout declined:\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end

  if voters.empty? && winfrey?
    puts "Skipped, everyone already voted:\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end

  unless @favorite_accounts.include? comment.author
    if @voting_rules.min_rep =~ /dynamic:[0-9]+/
      limit = @voting_rules.min_rep.split(':').last.to_i

      if (rep = comment.author_reputation.to_i) < min_trending_rep(limit)
        # ... rep too low ...
        puts "Skipped, due to low dynamic rep (#{('%.3f' % to_rep(rep))}):\n\t@#{comment.author}/#{comment.permlink}"
        return true
      end
    else
      if (rep = to_rep(comment.author_reputation)) < @voting_rules.min_rep
        # ... rep too low ...
        puts "Skipped, due to low rep (#{('%.3f' % rep)}):\n\t@#{comment.author}/#{comment.permlink}"
        return true
      end
    end

    if (rep = to_rep(comment.author_reputation)) > @voting_rules.max_rep
      # ... rep too high ...
      puts "Skipped, due to high rep (#{('%.3f' % rep)}):\n\t@#{comment.author}/#{comment.permlink}"
      return true
    end
  end

  downvoters = comment.active_votes.map do |v|
    v.voter if v.percent < 0
  end.compact

  if (signal = downvoters & @flag_signals).any?
    # ... Got a signal flag ...
    puts "Skipped, flag signals (#{signals.join(' ')} flagged):\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end

  upvoters = comment.active_votes.map do |v|
    v.voter if v.percent > 0
  end.compact

  if (signals = upvoters & @vote_signals).any?
    # ... Got a signal vote ...
    puts "Skipped, vote signals (#{signals.join(' ')} voted):\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end

  all_voters = comment.active_votes.map(&:voter)

  if (all_voters & voters).any?
    # ... Someone already voted (probably because post was edited) ...
    puts "Skipped, already voted:\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end

  if already_voted_for?(comment.author)
    # ... Already voted in timeframe ...
    puts "Skipped, already voted for @#{comment.author} within #{@voting_rules.unique_author} minutes"
    return true
  end

  false
end

def following?(voter, author)
  @voters_following ||= {}
  following = @voters_following[voter] || []
  count = -1

  if following.empty?
    until count == following.size
      count = following.size
      @follow_api.get_following(voter, following.last, 'blog', 100) do |result, error|
        if !!error
          puts "Unable to get follows for #{voter}: #{error}"
        end
        
        following += result.map(&:following)
        following = following.uniq
      end
    end

    @voters_following[voter] = following
  end

  @voters_following[voter] = nil if Random.rand(0..999) == 13

  following.include? author
end

def follower?(voter, author)
  @voters_followers ||= {}
  followers = @voters_followers[voter] || []
  count = -1

  if followers.empty?
    until count == followers.size
      count = followers.size
      @follow_api.get_followers(voter, followers.last, 'blog', 100) do |result, error|
        if !!error
          puts "Unable to get followers for #{voter}: #{error}"
        end
        
        followers += result.map(&:follower)
        followers = followers.uniq
      end
    end

    @voters_followers[voter] = nil if Random.rand(0..999) == 13

    @voters_followers[voter] = followers
  end

  followers.include? author
end

def vote_weight(author, voter)
  @semaphore.synchronize do
    if @favorite_accounts.include? author
      if @favorite_account_weights.keys.include? author
        @favorite_account_weights[author]
      else
        @voting_rules.favorites_vote_weight
      end
    elsif following? voter, author
      @voting_rules.following_vote_weight
    elsif follower? voter, author
      @voting_rules.followers_vote_weight
    else
      @voting_rules.vote_weight
    end
  end
end

def vote(comment, wait_offset = 0)
  votes_cast = 0
  backoff = 0.2
  slug = "@#{comment.author}/#{comment.permlink}"

  @threads.each do |k, t|
    @threads.delete(k) unless t.alive?
  end

  @semaphore.synchronize do
    if @threads.size != @last_threads_size
      print "Pending votes: #{@threads.size} ... "
      @last_threads_size = @threads.size
    end
  end

  if @threads.keys.include? slug
    puts "Skipped, vote already pending:\n\t#{slug}"
    return
  end

  @threads[slug] = Thread.new do
    comment = @api.get_content(comment.author, comment.permlink) do |comment, error|
      if !!error
        puts error.message
        return
      end
      
      comment
    end

    voters = if winfrey?
      @voters.keys - comment.active_votes.map(&:voter) - voters_recharging
    else
      @voters.keys
    end - voters_recharging

    return if skip?(comment, voters)

    if wait_offset == 0
      timestamp = Time.parse(comment.created + ' Z')
      now = Time.now.utc
      wait_offset = now - timestamp
    end

    if (wait = (Random.rand(*@voting_rules.wait_range) * 60) - wait_offset) > 0
      puts "Waiting #{wait.to_i} seconds to vote for:\n\t#{slug}"
      sleep wait

      @api.get_content(comment.author, comment.permlink) do |comment, error|
        if !!error
          puts "Unable to get comment @#{comment.author}/#{comment.permlink}: #{error}"
        end
        
        return if skip?(comment, voters)
      end
    else
      puts "Catching up to vote for:\n\t#{slug}"
      sleep 3
    end

    loop do
      begin
        break if voters.empty?

        author = comment.author
        permlink = comment.permlink
        voter = voters.sample
        weight = vote_weight(author, voter)

        break if weight == 0.0

        if (vp = @voting_power[voter].to_i) < @voting_rules.min_voting_power
          vp = vp / 100.0

          if @voters.size > 1
            puts "Recharging #{voter} vote power (currently too low: #{('%.3f' % vp)} %)"
          else
            puts "Recharging vote power (currently too low: #{('%.3f' % vp)} %)"
          end
        end

        wif = @voters[voter]
        tx = Radiator::Transaction.new(@chain_options.merge(wif: wif))

        puts "#{voter} voting for #{slug}"

        vote = {
          type: :vote,
          voter: voter,
          author: author,
          permlink: permlink,
          weight: weight
        }

        op = Radiator::Operation.new(vote)
        tx.operations << op
        response = tx.process(true)

        if !!response.error
          message = response.error.message
          if message.to_s =~ /You have already voted in a similar way./
            puts "\tFailed: duplicate vote."
            voters -= [voter]
            next
          elsif message.to_s =~ /Can only vote once every 3 seconds./
            if winfrey? || voters.size == 1
              puts "\tRetrying: voting too quickly."
              sleep 3
            else
              puts "\tSkipped: voting too quickly."
              voters -= [voter]
            end

            next
          elsif message.to_s =~ /Voting weight is too small, please accumulate more voting power or steem power./
            puts "\tFailed: voting weight too small"
            voters -= [voter]
            next
          elsif message.to_s =~ /STEEMIT_UPVOTE_LOCKOUT_HF17/
            puts "\tFailed: upvote lockout (last twelve hours before payout)"
            break
          elsif message.to_s =~ /tapos_block_summary/
            puts "Retrying: tapos_block_summary (?)"
            redo
          elsif message.to_s =~ /now < trx.expiration/
            puts "Retrying: now < trx.expiration (?)"
            redo
          elsif message.to_s =~ /signature is not canonical/
            puts "\tRetrying: signature was not canonical (bug in Radiator?)"
            redo
          end
          raise message
        end

        puts "\tSuccess: #{response.result.to_json}"
        votes_cast += 1

        if winfrey?
          # The winfrey mode keeps voting until there are no more voters of
          # until max_votes_per_post is reached (if set)

          if @voting_rules.max_votes_per_post.nil? || votes_cast < @voting_rules.max_votes_per_post
            voters -= [voter]
            next
          else
            puts "Max votes per post reached."
            break
          end
        end

        # The drphil mode only votes with one key per post.
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

puts "Current mode: #{@voting_rules.mode}.  Accounts voting: #{@voters.size}"
replay = 0
stream = true

ARGV.each do |arg|
  if arg =~ /replay:[0-9]+/
    replay = arg.split('replay:').last.to_i rescue 0
  end
  stream = false if arg == 'stream:false'
end

replay_threads = []

if replay > 0
  replay_threads << Thread.new do
    @api = Radiator::Api.new(@chain_options)
    @follow_api = Radiator::FollowApi.new(@chain_options)
    @stream = Radiator::Stream.new(@chain_options)

    properties = @api.get_dynamic_global_properties.result
    last_irreversible_block_num = properties.last_irreversible_block_num
    block_number = last_irreversible_block_num - replay

    puts "Replaying from block number #{block_number} ..."

    @api.get_blocks(block_number..last_irreversible_block_num) do |block, number|
      next unless !!block

      timestamp = Time.parse(block.timestamp + ' Z')
      now = Time.now.utc
      elapsed = now - timestamp

      block.transactions.each do |tx|
        tx.operations.each do |type, op|
          vote(op, elapsed.to_i) if type == 'comment' && may_vote?(op)
        end
      end
    end

    sleep 3
    puts "Done replaying."
  end
end

unless stream
  replay_threads.map(&:join)
  @threads.values.map(&:join)
  exit
end

puts "Now waiting for new posts."

loop do
  @api = Radiator::Api.new(@chain_options)
  @follow_api = Radiator::FollowApi.new(@chain_options)
  @stream = Radiator::Stream.new(@chain_options)
  op_idx = 0

  begin
    puts summary_voting_power

    @stream.operations(:comment) do |comment|
      next unless may_vote? comment

      if @max_voting_power < @voting_rules.min_voting_power
        vp = @max_voting_power / 100.0

        puts "Recharging vote power (currently too low: #{('%.3f' % vp)} %)"
      end

      vote(comment)
      puts summary_voting_power
    end
  rescue => e
    @api.shutdown
    puts "Unable to stream on current node.  Retrying in 5 seconds.  Error: #{e}"
    sleep 5
  end
end
