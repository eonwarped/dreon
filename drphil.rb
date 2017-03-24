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

@config_path = __FILE__.sub(/\.rb$/, '.yml')

unless File.exist? @config_path
  puts "Unable to find: #{@config_path}"
  exit
end

@config = YAML.load_file(@config_path)
@mode = @config['mode'] || 'drphil'
@voters = @config['voters'].map{ |v| v.split(' ')}.flatten.each_slice(2).to_h
@skip_accounts = @config['skip_accounts'].split(' ')
@skip_tags = @config['skip_tags'].split(' ')
@flag_signals = @config['flag_signals'].split(' ')
@vote_weight = @config['vote_weight']
@min_wait = @config['min_wait'].to_i
@max_wait = @config['max_wait'].to_i
@wait_range = [@min_wait..@max_wait]
@min_rep = @config['min_rep'].to_f
@options = {
  chain: @config['chain_options']['chain'].to_sym,
  url: @config['chain_options']['url'],
  logger: Logger.new(__FILE__.sub(/\.rb$/, '.log'))
}

def to_rep(raw)
  raw = raw.to_i
  neg = raw < 0
  level = Math.log10(raw.abs)
  level = [level - 9, 0].max
  level = (neg ? -1 : 1) * level
  level = (level * 9) + 25

  level
end

def may_vote?(comment)
  return false unless comment.parent_author.empty?
  return false if @skip_tags.include? comment.parent_permlink
  return false if (@skip_tags & JSON[comment.json_metadata || '{}']['tags'] rescue []).any?
  return false if @skip_accounts.include? comment.author
  
  true
end

def skip?(comment, voters)
  if voters.empty? && @mode == 'winfrey'
    puts "Skipped, everyone already voted:\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end
  
  all_voters = comment.active_votes.map(&:voter)
  downvoters = comment.active_votes.map do |v|
    v.voter if v.percent < 0
  end.compact
  
  # Skipping this post because of various reasons like
  if (rep = to_rep(comment.author_reputation)) < @min_rep
    # ... rep too low ...
    puts "Skipped, due to low rep (#{('%.3f' % rep)}):\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end
  
  if (downvoters & @flag_signals).any?
    # ... Got a signal flag ...
    puts "Skipped, flag signals:\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end
  
  if (all_voters & voters).any?
    # ... Someone already voted (probably because post was edited) ...
    puts "Skipped, already voted:\n\t@#{comment.author}/#{comment.permlink}"
    return true
  end
  
  false
end

def vote(comment)
  backoff = 0.2
  
  Thread.new do
    response = @api.get_content(comment.author, comment.permlink)
    comment = response.result
    
    voters = if @mode == 'winfrey'
      @voters.keys - comment.active_votes.map(&:voter)
    else
      @voters.keys
    end
    
    return if skip?(comment, voters)
    
    wait = Random.rand(*@wait_range) * 60
    puts "Waiting #{wait} seconds to vote for:\n\t@#{comment.author}/#{comment.permlink}"
    sleep wait
    
    response = @api.get_content(comment.author, comment.permlink)
    comment = response.result
    
    return if skip?(comment, voters)
    
    loop do
      begin
        break if voters.empty?
        
        author = comment.author
        permlink = comment.permlink
        voter = voters.sample
        
        wif = @voters[voter]
        tx = Radiator::Transaction.new(@options.merge(wif: wif))
        
        puts "#{voter} voting for @#{author}/#{permlink}"
        
        vote = {
          type: :vote,
          voter: voter,
          author: author,
          permlink: permlink,
          weight: (@vote_weight.to_f * 100).to_i
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
          elsif message.to_s =~ /Voting weight is too small, please accumulate more voting power or steem power./
            voters -= [voter]
            next
          end
          raise message
        end
        
        puts "\tSuccess: #{response.result.to_json}"
        
        if @mode == 'winfrey'
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

puts "Current mode: #{@mode}.  Accounts voting: #{@voters.size} ... waiting for posts."

loop do
  @api = Radiator::Api.new(@options)
  @stream = Radiator::Stream.new(@options)

  begin
    @stream.operations(:comment) do |comment|
      next unless may_vote? comment
      
      vote(comment)
    end
  rescue => e
    puts "Unable to stream on current node.  Retrying in 5 seconds.  Error: #{e}"
    sleep 5
  end
end
