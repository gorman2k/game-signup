require 'mongo'
include Mongo

db = Connection.new.db('poker')
users = db.collection('users')

begin
	file = File.new("emails.txt", "r")
	while (line = file.gets)
		email = "#{line}".chomp
		new_user = { :email => "#{email}", :created_on => Time.now }
		users.insert(new_user)
	end
	file.close
rescue => err
    	puts "Exception: #{err}"
    	err
end

puts "All done!"