# Dr. Phil (drphil) is reimplmentation of the winfrey voting bot.  The goal is
# to give everyone an upvote.  But instead of voting 1% by 100 accounts like
# winfrey, this script will vote 100% with 1 randomly chosen account.
# 
# See: https://steemit.com/radiator/@inertia/drphil-rb-voting-bot

require 'rubygems'
require 'bundler/setup'
require 'yaml'
require 'pry'

Bundler.require

# If there are problems, this is the most time we'll wait (in seconds).
MAX_BACKOFF = 12.8

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
  favorites_vote_weight: (((rules['favorites_vote_weight'] || '100.0 %').to_f) * 100).to_i,
  following_vote_weight: (((rules['following_vote_weight'] || '100.0 %').to_f) * 100).to_i,
  followers_vote_weight: (((rules['followers_vote_weight'] || '100.0 %').to_f) * 100).to_i,
  enable_comments: rules['enable_comments'],
  only_first_posts: rules['only_first_posts'],
  min_wait: rules['min_wait'].to_i,
  max_wait: rules['max_wait'].to_i,
  min_rep: (rules['min_rep'] || 25.0),
  max_rep: (rules['max_rep'] || 99.9).to_f,
  min_voting_power: (((rules['min_voting_power'] || '0.0 %').to_f) * 100).to_i
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
@flag_signals = parse_list(@config['flag_signals'])
@vote_signals = parse_list(@config['vote_signals'])
  
@options = {
  chain: @config['chain_options']['chain'].to_sym,
  url: @config['chain_options']['url'],
  logger: Logger.new(__FILE__.sub(/\.rb$/, '.log'))
}

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
    response = @api.get_accounts(@voters.keys)
    accounts = response.result
    
    @voting_power = {}
    
    accounts.each do |account|
      @voting_power[account.name] = account.voting_power
    end
    
    @min_voting_power = accounts.map(&:voting_power).min
    @max_voting_power = accounts.map(&:voting_power).max
    @average_voting_power = accounts.map(&:voting_power).inject(:+) / accounts.size
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

def voters_check_charging
  @semaphore.synchronize do
    return [] if (Time.now.utc.to_i - @voters_check_charging_at.to_i) < 300
    
    @voters_check_charging_at = Time.now.utc
    
    @voting_power.map do |voter, power|
      if power < @voting_rules.min_voting_power
        check_time = 4320 # TODO Make this dynamic based on effective voting power
        response = @api.get_account_votes(voter)
        votes = response.result
        latest_vote_at = if votes.any? && !!(time = votes.last.time)
          Time.parse(time + 'Z')
        end
        
        elapsed = Time.now.utc.to_i - latest_vote_at.to_i
        
        voter if elapsed > check_time
      end
    end.compact
  end
end

def tags_intersection?(json_metadata)
  metadata = JSON[json_metadata || '{}']
  tags = metadata['tags'] || [] rescue []
  
  (@skip_tags & tags).any?
end

def may_vote?(comment)
  return false if !@voting_rules.enable_comments && !comment.parent_author.empty?
  return false if @skip_tags.include? comment.parent_permlink
  return false if tags_intersection? comment.json_metadata
  return false if @skip_accounts.include? comment.author
  
  true
end

def min_trending_rep(limit)
  begin
    @semaphore.synchronize do
      if @min_trending_rep.nil? || Random.rand(0..limit) == 13
        puts "Looking up trending up to #{limit} posts."
        
        response = @api.get_discussions_by_trending(tag: '', limit: limit)
        raise response.error.message if !!response.error
        
        trending = response.result
        @min_trending_rep = trending.map do |c|
          c.author_reputation.to_i
        end.min
        
        puts "Current minimum dynamic rep: #{('%.3f' % to_rep(@min_trending_rep))}"
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
        response = @api.get_accounts([comment.author])
        account = response.result.last
        
        if account.post_count > 1
          puts "Skipped, not first post:\n\t@#{comment.author}/#{comment.permlink}"
          return true
        end
      end
    rescue => e
      puts "Warning: #{e}"
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
  
  false
end

def following?(voter, author)
  @voters_following ||= {}
  following = @voters_following[voter] || []
  count = -1
  
  if following.empty?
    until count == following.size
      count = following.size
      response = @follow_api.get_following(voter, following.last, 'blog', 100)
      following += response.result.map(&:following)
      following = following.uniq
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
      response = @follow_api.get_followers(voter, followers.last, 'blog', 100)
      followers += response.result.map(&:follower)
      followers = followers.uniq
    end
    
    @voters_followers[voter] = nil if Random.rand(0..999) == 13
  
    @voters_followers[voter] = followers
  end
  
  followers.include? author
end

def vote_weight(author, voter)
  @semaphore.synchronize do
    if @favorite_accounts.include? author
      @voting_rules.favorites_vote_weight
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
    response = @api.get_content(comment.author, comment.permlink)
    
    if !!response.error
      puts response.error.message
      return
    end
    
    comment = response.result
    check_charging = voters_check_charging
    
    voters = if winfrey?
      @voters.keys - comment.active_votes.map(&:voter) - voters_recharging
    else
      @voters.keys
    end - voters_recharging + check_charging
    
    return if skip?(comment, voters)
    
    if wait_offset == 0
      timestamp = Time.parse(comment.created + ' Z')
      now = Time.now.utc
      wait_offset = now - timestamp
    end
    
    if (wait = (Random.rand(*@voting_rules.wait_range) * 60) - wait_offset) > 0
      puts "Waiting #{wait.to_i} seconds to vote for:\n\t#{slug}"
      sleep wait
      
      response = @api.get_content(comment.author, comment.permlink)
      comment = response.result
      
      return if skip?(comment, voters)
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
          
          unless check_charging.include? voter
            voters -= [voter]
            next
          end
        end
                
        wif = @voters[voter]
        tx = Radiator::Transaction.new(@options.dup.merge(wif: wif))
        
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
          end
          raise message
        end
        
        puts "\tSuccess: #{response.result.to_json}"
        
        if winfrey?
          # The winfrey mode keeps voting until there are no more voters.
          voters -= [voter]
          next
        end
        
        # The drphil mode only votes with one key.
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
  
ARGV.each do |arg|
  if arg =~ /replay:[0-9]+/
    replay = arg.split('replay:').last.to_i rescue 0
  end
end

if replay > 0
  Thread.new do
    @api = Radiator::Api.new(@options.dup)
    @follow_api = Radiator::FollowApi.new(@options.dup)
    @stream = Radiator::Stream.new(@options.dup)
    
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

puts "Now waiting for new posts."

loop do
  @api = Radiator::Api.new(@options.dup)
  @follow_api = Radiator::FollowApi.new(@options.dup)
  @stream = Radiator::Stream.new(@options.dup)
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
