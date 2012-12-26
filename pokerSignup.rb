require 'sinatra'
require 'sinatra/flash'
require "sinatra/reloader" if development?
require 'mongo_mapper'
require 'haml'

enable :sessions

class User
  include MongoMapper::Document

  key :email, String, :required => true
  key :firstName, String
  key :lastName, String
  key :lastLoginTime, Time
  key :currentLoginTime, Time
  key :admin, Boolean
end

class Game
  include MongoMapper::Document

  key :date, Time
  key :maxPlayers, Integer
  key :minPlayers, Integer
  key :userIds, Array
  many :users, :in => :user_ids
  key :waitingListIds, Array
  many :users, :in => :waitingList_ids
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
end

configure do
  Time.zone_default = 'Central Time (US & Canada)'

  set :haml, {:format => :html5}
  $stdout.sync = true
  mongo_uri = "mongodb://localhost/poker" || ENV['MONGOHQ_URL']
  MongoMapper.connection = Mongo::MongoClient.from_uri(mongo_uri)
end

#######################################################

get "/games" do
  if logged_in?
    @user = User.first(:id => session[:user])

    if (@user.firstName.nil? or @user.lastName.nil?)
      redirect "/user/#{session[:user]}"
    end

    @upcomingGames = Game.where(:date.gt => Time.now)
    @pastGames = Game.where(:date.lt => Time.now).sort(:date.desc).limit(5)

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
    @user = User.first(:id => "#{params[:id]}")
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
    @user = User.first(:id => session[:user])
    @user.set(:firstName => params[:firstName])
    @user.set(:lastName => params[:lastName])

    flash[:info] = "User details updated"
    redirect "/"
  else
    haml :login
  end
end

get "/game/:id" do
  if logged_in?
    @user = User.first(:id => session[:user])
    game = Game.find("#{params[:id]}")

    @playerIds = game.userIds
    @players = []
    @playerIds.each do |playerId|
      @players << User.find(playerId)
    end

    @waitingListPlayerIds = game.waitingListIds
    @waitingListPlayers = []
    @waitingListPlayerIds.each do |playerId|
      @waitingListPlayers << User.find(playerId)
    end
    if "#{@user.admin}" == "true"
      adminUser = true
      haml :game, :locals => {:game => game, :adminUser => adminUser}
    else
      haml :game, :locals => {:game => game}
    end
  else
    haml :login
  end
end

put "/game/:id" do
  if logged_in?
    game = Game.find("#{params[:id]}")

    # don't allow modifications to games in the past
    if (game.date < Time.now)
      flash[:error] = "Modifications to past games are not allowed"
    else

      # if the game isn't full, add the player
      if (game.userIds.length < game.maxPlayers)
        game.push_uniq(:userIds => "#{session[:user]}")
      else

        # make sure they're not already in the game
        # otherwise add them to the waiting list
        if (!game.userIds.include? "#{session[:user]}")
          flash[:info] = "The game is full but you will be added to the waiting list"
          game.push_uniq(:waitingListIds => "#{session[:user]}")
        end
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
      game.pull(:waitingListIds => "#{session[:user]}")
      game.pull(:userIds => "#{session[:user]}")

      # refresh game object
      game = Game.find("#{params[:id]}")

      # see if there's a waiting list so they can be added to the game
      if (game.waitingListIds.any? and (game.userIds.length < game.maxPlayers))
        ids = game.waitingListIds
        idToAdd = ids.shift
        game.waitingListIds = ids
        game.save!
        game.push_uniq(:userIds => idToAdd)
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
    @user = User.first(:id => session[:user])
    if "#{@user.admin}" == "true"
      haml :admin
    else
      redirect "/"
    end
  else
    haml :login
  end
end

post "/user/authenticate" do
  user = User.first(:email => params[:email])

  if !user
    flash[:error] = "User doesn't exist"
    redirect "/"
  end

  user.lastLoginTime = user.currentLoginTime
  user.currentLoginTime = Time.now
  if user.save
    session[:user] = user.id
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
    @user = User.first(:id => session[:user])
    haml :about
  else
    haml :login
  end
end