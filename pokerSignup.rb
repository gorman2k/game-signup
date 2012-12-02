require 'sinatra'
require "sinatra/reloader" if development?
require 'mongo_mapper'
require 'json'
require 'haml'
require "digest/sha2"

enable :sessions

helpers do
	def generate_salt
		rng = Random.new
		Array.new(32){ rng.rand(33...126).chr }.join
	end
	
	def logged_in?
		if session[:user]
			true
		else
			false
		end
	end
	
	#Flash helper based on the one from here:
	#https://github.com/daddz/sinatra-dm-login/blob/master/helpers/sinatra.rb
	def show_flash(key)
		if session[key]
			flash = session[key]
			session[key] = false
			flash
		end
	end
end

module PasswordHasher
	def hash_password(password, salt)
		Digest::SHA2.hexdigest(password+salt)
	end
end

include PasswordHasher

class User
	include MongoMapper::Document
	include PasswordHasher
	
	key :username, String
	key :email, String, :required => true
	key :salt, String
	key :hashed_password, String, :length => 64
	key :last_login_time, DateTime, :required => false
	key :last_login_ip, String, :required => false
	key :current_login_time, DateTime
	key :current_login_ip, String
	
	validates_uniqueness_of :name, :message => "has already been taken"
	validates_length_of :name, :in => 3..16, :message => "must be between 3 and 16 characters"
	
	def authenticate(password)
		if (hash_password(password, salt)).eql?(hashed_password)
			true
		else
			false
		end
	end
end

configure do
  $stdout.sync = true
  #mongo_uri = ENV['connectionString']
  mongo_uri = "mongodb://localhost"
  MongoMapper.connection = Mongo::Connection.from_uri(mongo_uri)
  #MongoMapper.database = ENV['databaseName']
  MongoMapper.database = "poker"
end

get "/" do
	if logged_in?
		@user = User.first(:hashed_password => session[:user])
	end
	erb :index
end

post "/user/authenticate" do
	user = User.first(:name => params[:name])
	
	if !user
		session[:flash] = "User doesn't exist"
		redirect "/"
	end
	
	authenticated = user.authenticate(params[:password])
	
	if authenticated
		user.last_login_time = user.current_login_time
		user.last_login_ip = user.current_login_ip
		user.current_login_time = DateTime.now
		user.current_login_ip = request.ip
		if user.save
			session[:user] = user.hashed_password
		else
			session[:flash] = "There was an error logging in, please try again"
		end
	else
		session[:flash] = "Incorrect Password"
	end
	
	redirect "/"
end

post "/user/logout" do
	session[:user] = nil
	session[:flash] = "You have logged out successfully"
	redirect "/"
end

get "/signup" do
	erb :signup
end

post "/user/create" do
	user = User.first(:name => params[:name])
	
	if user
		session[:flash] = "That username has been taken"
		redirect "/signup"
	end
	
	if !params[:password].eql?(params[:password2])
		session[:flash] = "You entered two different passwords"
		redirect "/signup"
	end
	
	salt = generate_salt
	hashed_password = hash_password(params[:password], salt)
	user = User.new({
		:name => params[:name],
		:salt => salt,
		:hashed_password => hashed_password,
		:current_login_time => Time.now,
		:current_login_ip => request.ip
	})
	
	if user.save
		session[:flash] = "Signed up successfully"
		session[:user] = user.hashed_password
		redirect "/"
	else
		session[:flash] = user.errors.full_messages.first
		redirect "/"
	end
	
	#also check to make sure password is a certain length, contains an uppercase character, number, lowercase letter etc.
end

__END__

@@ layout
<html>
	<head>
		<title>User Login Test</title>
	</head>
	
	<body>
		<h1>User Login Test</h2>
	
		<%= yield %>
	</body>
</html>

@@ index
<% if session[:flash] %>
	<p><%= show_flash(:flash) %></p>
<% end %>

<% if !@user %>
	<form action="/user/authenticate" method="post">
		Username <input type="text" name="name"/><br/>
		Password <input type="password" name="password"/><br/>
		<input type="submit" value="Login"/>
	</form>
	
	<p><a href="/signup">Or signup for free today!</a></p>
<% else %>
	<p>Hello <%= @user.name %></p>
	<% if @user.last_login_time %>
		<p>Last account activity: <%= @user.last_login_time %> <%= @user.last_login_ip %></p>
	<% else %>
		<p>This is your first time in the system</p>
	<% end %>	
	
	<form action="/user/logout" method="post">
		<input type="submit" value="logout"/>
	</form>
<% end %>

@@ signup
<% if session[:flash] %>
	<p><%= show_flash(:flash) %></p>
<% end %>

<form action="/user/create" method="post">
	Username: <input type="text" name="name"/><br/>
	Password: <input type="password" name="password"/><br/>
	Confirm Password: <input type="password" name="password2"/><br/>
	<input type="submit" value="signup"/>
</form>