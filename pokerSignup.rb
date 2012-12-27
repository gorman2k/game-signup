require 'sinatra'
require 'sinatra/flash'
require "sinatra/reloader" if development?
require 'mongoid'
require 'haml'

enable :sessions

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
  field :userIds, type: Array
  field :waitingListIds, type: Array
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

  def flash_types
    [:success, :info, :warning, :error]
  end

  def get_errors_for(object)
    allerrors = ""
    object.errors.each{|attr,msg| allerrors += ("#{attr} #{msg}<br>") }
    allerrors
  end
end

configure do
  Time.zone_default = 'Central Time (US & Canada)'
  set :haml, {:format => :html5}
  $stdout.sync = true
  Mongoid.configure do |config|
    config.sessions = {
        :default => {
            :hosts => ["localhost:27017"], :database => "poker"
        }
    }
    end
end

#######################################################

get "/games" do
  if logged_in?
    @user = User.where(id: session[:user]).first

    if (@user.firstName.nil? or @user.lastName.nil?)
      redirect "/user/#{session[:user]}"
    end

    @upcomingGames = Game.where(:date.gt => Time.now)
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

    redirect "/"
  else
    haml :login
  end
end

get "/game/:id" do
  if logged_in?
    @user = User.where(:id => session[:user]).first
    game = Game.find("#{params[:id]}")

    @playerIds = game.userIds
    @players = []
    if !@playerIds.nil?
      @playerIds.each do |playerId|
        @players << User.find(playerId)
      end
    end

    @waitingListPlayerIds = game.waitingListIds
    @waitingListPlayers = []
    if !@waitingListPlayerIds.nil?
      @waitingListPlayerIds.each do |playerId|
        @waitingListPlayers << User.find(playerId)
      end
    end

    haml :game, :locals => {:game => game}
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
      if game.userIds.nil? or (game.userIds.length < game.maxPlayers)
        game.add_to_set(:userIds, "#{session[:user]}")
      end

      # make sure they're not already in the game
      # otherwise add them to the waiting list
      if (!game.userIds.include? "#{session[:user]}")
        flash[:info] = "The game is full but you will be added to the waiting list"
        game.add_to_set(:waitingListIds, "#{session[:user]}")
      end
    end

    redirect "/game/#{params[:id]}"
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
      game.pull(:waitingListIds, "#{session[:user]}")
      game.pull(:userIds, "#{session[:user]}")

      # refresh game object
      game = Game.find("#{params[:id]}")

      # see if there's a waiting list so they can be added to the game
      if !game.waitingListIds.nil? and (game.userIds.length < game.maxPlayers)
        ids = game.waitingListIds
        idToAdd = ids.shift
        game.waitingListIds = ids
        game.save
        game.add_to_set(:userIds, idToAdd)
      end
    end

    redirect "/game/#{params[:id]}"
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
    @user = User.where(:id => session[:user]).first
    @upcomingGames = Game.where(:date.gt => Time.now)

    gameEmailHash = Hash.new
    @upcomingGames.each do |game|
      emails = Array.new

      @playerIds = game.userIds
      if !@playerIds.nil?
        @playerIds.each do |playerId|
          player = User.find(playerId)
          emails.push(player.email)
        end
      end

      @waitingListPlayerIds = game.waitingListIds
      if !@waitingListPlayerIds.nil?
        @waitingListPlayerIds.each do |playerId|
          player = User.find(playerId)
          emails.push(player.email)
        end
      end

      gameEmailHash[game.date] = emails
    end

    haml :admin, :locals => {:gameEmailHash => gameEmailHash}
  else
    haml :login
  end
end

post "/user/authenticate" do
  @user = User.where(:email => params[:email]).first

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