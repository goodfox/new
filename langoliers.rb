#!/usr/bin/env ruby
require 'rubygems'
require 'twitter'
require 'json'
require 'faraday'

# things you must configure
PATH_TO_DROPBOX = "/Users/your_name/Dropbox/backup/tweets/" # you need to create this folder
TWITTER_USER = "your_twitter_username"

# get these from dev.twitter.com
CONSUMER_KEY = "your_consumer_key"
CONSUMER_SECRET = "your_consumer_secret"
OAUTH_TOKEN = "your_oauth_token"
OAUTH_TOKEN_SECRET = "your_oauth_token_secret"

# things you might want to change
MAX_AGE_IN_DAYS = 10 # anything older than this is deleted / unfavorited
DELAY_BETWEEN_DELETES = 0.5 # in seconds
DELAY_BETWEEN_REQS = 45

# save tweets that have been massively favorited??? nah. all is vanity.
FAVE_THRESHOLD = 9999

# don't delete these (maybe a pinned tweet? an old favorite? whatever)
IDS_TO_SAVE_FOREVER = [519676643829231616]

# you don't need to mess with this
API_TWEET_MAX = 3200
TWEETS_PER_PAGE = 200 # api max is 250 or something... 200 seems like a nice round number
NUM_PAGES = (API_TWEET_MAX / TWEETS_PER_PAGE).to_i
MAX_AGE_IN_SECONDS = MAX_AGE_IN_DAYS*24*60*60
NOW_IN_SECONDS = Time.now

FIELDS = [:id,
        :created_at,
        :text,
        :retweet_count,
        :in_reply_to_screen_name,
        :in_reply_to_user_id,
        :in_reply_to_status_id]

# tweet methods

client = Twitter::REST::Client.new do |config|
  config.consumer_key        = CONSUMER_KEY
  config.consumer_secret     = CONSUMER_SECRET
  config.access_token        = OAUTH_TOKEN
  config.access_token_secret = OAUTH_TOKEN_SECRET
end

def save_to_dropbox(tweet)
  slender_tweet = {}
  FIELDS.each do |field|
    slender_tweet[field] = tweet[field].to_s
  end
  slender_tweet[:urls] = tweet.urls

  time_string = Time.parse(slender_tweet[:created_at]).to_i.to_s
  file_name = "#{time_string}_#{slender_tweet[:id]}.json"
  full_path = PATH_TO_DROPBOX+file_name
  puts "Saving tweet to #{full_path}"

  f = File.new(full_path,'w')
  f.puts slender_tweet.to_json
  f.close

  tweet.media.each do |media,i|
    url = media.media_url
    puts "Saving image #{url}"
    http_conn = Faraday.new do |builder|
      builder.adapter Faraday.default_adapter
    end
    response = http_conn.get(url)
    media_path = full_path.gsub(".json","")+"_media_"+File.basename(url)
    File.open(media_path, 'wb') do |f|
      f.write(response.body)
    end
  end
end

def delete_from_twitter(tweet,client)
  begin
    client.destroy_status(tweet.id)
  rescue StandardError => e
    puts e.inspect
    puts "Error deleting #{tweet.id}; exiting hard"
    exit
  else
    puts "Deleted"
  end
end

# init twitter

puts ""
puts "What's that sound...?"
puts ""

timeline = []

begin
  tweet_max = client.user(TWITTER_USER).statuses_count < 3200 ? client.user(TWITTER_USER).statuses_count : API_TWEET_MAX
  oldest_page = (tweet_max / TWEETS_PER_PAGE).to_i # we go to this page -- the older tweets -- first
  puts "Oldest page is #{oldest_page}"
rescue StandardError => e
  puts e
  puts "Error getting info about @#{TWITTER_USER}. Try again."
  exit
end

error_count = 0

4.times do |i|
  begin
    puts "Requesting tweets #{i*TWEETS_PER_PAGE}-#{(i+1)*TWEETS_PER_PAGE}"
    timeline = timeline.concat(client.user_timeline(TWITTER_USER,{:count=>TWEETS_PER_PAGE,:page=>i,:include_entities=>true,:include_rts=>true}))
  rescue
    error_count += 1
    if (error_count > 5) then
      puts "Too many errors! Try again later."
      exit
    else
      puts "Error getting tweets #{oldest_page*TWEETS_PER_PAGE}-#{tweet_max}, retrying after #{2**error_count} seconds..."
      sleep(2**error_count)
      retry
    end
  end
end

puts "Got #{timeline.size} tweets"
puts ""

timeline.each do |tweet|
  tweet_age = NOW_IN_SECONDS - tweet.created_at

  if (tweet_age < MAX_AGE_IN_SECONDS) then
    puts "Ignored a tweet #{(tweet_age/(24*60*60)).round} days old"
  elsif (tweet.favorite_count >= FAVE_THRESHOLD) then
    puts "Ignored a tweet with #{tweet.favorite_count} faves"
  elsif IDS_TO_SAVE_FOREVER.include?(tweet.id) then
    puts "Ignored a tweet that is to be saved forever"
  else
    puts "Preparing to delete a tweet #{(tweet_age/(24*60*60)).round} days old"

    begin
      save_to_dropbox(tweet)
    rescue StandardError => e
      puts e.inspect
      puts "Error saving #{tweet.id}; exiting hard"
      exit
    else
      delete_from_twitter(tweet,client)
    end
  end

  puts "  #{tweet.text}"
  puts ""

  sleep DELAY_BETWEEN_DELETES
end

