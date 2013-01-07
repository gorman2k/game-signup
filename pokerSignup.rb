require 'sinatra'
require 'sinatra/flash'
require "sinatra/reloader" if development?
require 'mongoid'
require 'haml'
configure :production do
  require 'newrelic_rpm'
end

enable :sessions
Mongoid.load!("config/mongoid.yml")

class User
  include Mongoid::Document

  field :email, type: String
  field :firstName, type: String
  field :lastName, type: String
  field :lastLoginTime, type: Time

  validates_length_of :firstName, minimum: 2
  validates_length_of :lastName,  minimum: 2
end

class Game
  include Mongoid::Document

  field :date, type: Time
  field :maxPlayers, type: Integer
  field :minPlayers, type: Integer
  field :playerIds, type: Hash, default: Hash.new
  field :waitingListIds, type: Hash, default: Hash.new
end

#######################################################

helpers do
  def logged_in?
    if session[:user]
      true
    else
      false
    end
  end

  def get_errors_for(object)
    allerrors = ""
    object.errors.each{|attr,msg| allerrors += ("#{attr} #{msg}<br>") }
    allerrors
  end

  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [ENV['adminUser'], ENV['adminPassword']]
  end

  def get_player_list(id)
    @game = Game.find(id)

    @players = Hash.new
    @game.playerIds.each do |playerId, signupTime|
      @players[User.find(playerId)] = signupTime
    end
    @players = @players.sort_by { |player, signupTime| signupTime }
    return @players
  end

  def get_waiting_list(id)
    @game = Game.find(id)

    @waitingListPlayers = Hash.new
    @game.waitingListIds.each do |playerId, signupTime|
      @waitingListPlayers[User.find(playerId)] = signupTime
    end
    @waitingListPlayers = @waitingListPlayers.sort_by { |player, signupTime| signupTime }
  end

  def flash_message
    [:error, :info, :success].each do |type|
      return flash[type] unless flash[type].blank?
    end
  end

  def flash_type
    [:error, :info, :success].each do |type|
      return type unless flash[type].blank?
    end
  end
end

configure do
  Time.zone_default = 'Central Time (US & Canada)'
  set :haml, {:format => :html5}
end

before do
  return unless request.xhr?
  response.headers['X-Message'] = flash[:info]  unless flash[:info].blank?
  response.headers['X-Message'] = flash[:success]  unless flash[:success].blank?
  response.headers['X-Message'] = flash[:error]  unless flash[:error].blank?
  response.headers['X-Message-Type'] = flash_type.to_s
  flash.discard
end

#######################################################

get "/games" do
  if logged_in?
    @user = User.where(id: session[:user]).first

    if (@user.firstName.nil? or @user.lastName.nil?)
      redirect "/user/#{session[:user]}"
    end

    @upcomingGames = Game.where(:date.gt => Time.now).desc(:date)
    @pastGames = Game.where(:date.lt => Time.now).desc(:date).limit(10)

    haml :index
  else
    haml :login
  end
end

get "/" do
  if logged_in?
    redirect "/games"
  else
    haml :login
  end
end

get "/user/:id" do
  if logged_in?
    @user = User.where(:id => "#{params[:id]}").first
    haml :user
  else
    haml :login
  end
end

get "/user" do
  if logged_in?
    redirect "/user/#{session[:user]}"
  else
    haml :login
  end
end

put "/user/:id" do
  if logged_in?
    @user = User.where(:id => session[:user]).first
    @user.firstName = params[:firstName]
    @user.lastName = params[:lastName]

    # only for logging in for the first time without a name set
    if @user.lastLoginTime.nil?
      @user.lastLoginTime = Time.now
    end

    if @user.save
      flash[:info] = "User details updated"
    else
      flash[:error] = get_errors_for(@user)
      redirect "/user/#{session[:user]}"
    end

    redirect "/user/#{params[:id]}"
  else
    haml :login
  end
end

get "/game/:id/playerList" do
  if logged_in?
    get_player_list("#{params[:id]}")
    haml :playerList, :layout => false
  end
end

get "/game/:id/waitingList" do
  if logged_in?
    get_waiting_list("#{params[:id]}")
    haml :waitingList, :layout => false
  end
end

get "/game/:id" do
  if logged_in?
    @user = User.where(:id => session[:user]).first

    get_player_list("#{params[:id]}")
    get_waiting_list("#{params[:id]}")

    haml :game
  else
    haml :login
  end
end

put "/game/:id" do
  if logged_in?
    game = Game.find("#{params[:id]}")

    # don't allow modifications to games in the past
    if game.date < Time.now
      flash[:error] = "Modifications to past games are not allowed"
    else

      # if the game isn't full, add the player
      if game.playerIds.length < game.maxPlayers and !game.playerIds.keys.include? "#{session[:user]}"
        game.set("playerIds.#{session[:user]}", Time.now)
      end

      game = Game.find("#{params[:id]}")

      # make sure they're not already in the game
      # otherwise add them to the waiting list
      if !game.playerIds.keys.include? "#{session[:user]}" and !game.waitingListIds.keys.include? "#{session[:user]}"
        game.set("waitingListIds.#{session[:user]}", Time.now)
        flash[:info] = "The game is full but you will be added to the waiting list"
      end
    end
  else
    haml :login
  end
end

delete "/game/:id" do
  if logged_in?
    game = Game.find("#{params[:id]}")

    if (game.date < Time.now)
      flash[:error] = "Modifications to past games are not allowed"
    else

      # remove the userid from both the game and wait lists to be safe
      game.unset("waitingListIds.#{session[:user]}")
      game.unset("playerIds.#{session[:user]}")

      # refresh game object
      game = Game.find("#{params[:id]}")

      # see if there's a waiting list so they can be added to the game
      if !game.waitingListIds.empty? and (game.playerIds.length < game.maxPlayers)
        waitingListIds = game.waitingListIds.sort_by { |player, signupTime| signupTime }
        idToAddToGame, signupTime = waitingListIds.first

        # remove from waiting list
        game.unset("waitingListIds.#{idToAddToGame}")

        # add to player list
        game.set("playerIds.#{idToAddToGame}", signupTime)
      end
    end

  else
    haml :login
  end
end

post "/game" do
  if logged_in?
    game = Game.create({
            :date => Time.parse(params[:gameTime]),
            :maxPlayers => params[:maxPlayers],
            :minPlayers => params[:minPlayers]
    })

    game.save
    redirect "/"
  else
    haml :login
  end
end

get "/admin" do
  if logged_in?
    protected!

    @user = User.where(:id => session[:user]).first
    upcomingGames = Game.where(:date.gt => Time.now)

    # populate email addresses for upcoming games
    @gameEmailHash = Hash.new
    upcomingGames.each do |game|
      emails = Array.new

      game.playerIds.each do |playerId, signupTime|
        player = User.find(playerId)
        emails.push(player.email)
      end

      game.waitingListIds.each do |playerId, signupTime|
        player = User.find(playerId)
        emails.push(player.email)
      end

      @gameEmailHash[game.date] = emails
    end

    # last few logins
    @lastUsers = User.desc(:lastLoginTime).limit(10)

    haml :admin
  else
    haml :login
  end
end

post "/user/authenticate" do
  @user = User.where(:email => params[:email].downcase).first

  if @user.nil?
    flash[:error] = "User doesn't exist"
    redirect "/"
  end

  # first time logging in and the names are not populated in the DB
  # let them log in but redirect them to edit account
  if @user.lastLoginTime.nil? and (@user.firstName.nil? or @user.lastName.nil?)
    session[:user] = @user.id
    redirect "/user/#{session[:user]}"
  end

  @user.lastLoginTime = Time.now
  if @user.save
    session[:user] = @user.id
  else
    flash[:error] = "There was an error logging in, please try again"
  end

  redirect "/"
end

post "/signout" do
  session[:user] = nil
  flash[:success] = "You have logged out successfully"
end

get "/signup" do
  haml :signup
end

get "/about" do
  if logged_in?
    @user = User.where(:id => session[:user]).first
    haml :about
  else
    haml :login
  end
end
