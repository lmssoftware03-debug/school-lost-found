require 'sinatra'
require 'sqlite3'
require 'fileutils'

enable :sessions

# Upload folder setup
UPLOAD_DIR = 'public/uploads'
FileUtils.mkdir_p(UPLOAD_DIR) unless Dir.exist?(UPLOAD_DIR)

# Initialize SQLite Database
DB = SQLite3::Database.new('school_portal.db')
DB.results_as_hash = true

# Create Tables
DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    role TEXT NOT NULL
  );
SQL

DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    category TEXT NOT NULL,
    location TEXT NOT NULL,
    description TEXT,
    image_path TEXT,
    contact TEXT NOT NULL,
    user_id INTEGER,
    status TEXT DEFAULT 'Lost',
    FOREIGN KEY(user_id) REFERENCES users(id)
  );
SQL

# Seed default accounts if database is empty
if DB.execute("SELECT COUNT(*) as count FROM users").first['count'] == 0
  DB.execute("INSERT INTO users (username, password, role) VALUES (?, ?, ?)", ['admin', '1234', 'Admin'])
  DB.execute("INSERT INTO users (username, password, role) VALUES (?, ?, ?)", ['teacher1', '1234', 'Teacher'])
  DB.execute("INSERT INTO users (username, password, role) VALUES (?, ?, ?)", ['student1', '1234', 'Student'])
end

# --- AUTHENTICATION ROUTES ---

get '/login' do
  erb :login
end

post '/login' do
  user = DB.execute("SELECT * FROM users WHERE username = ? AND password = ?", [params[:username], params[:password]]).first
  if user
    session[:user_id] = user['id']
    session[:username] = user['username']
    session[:role] = user['role']
    redirect '/'
  else
    @error = "Invalid username or password!"
    erb :login
  end
end

get '/signup' do
  erb :signup
end

post '/signup' do
  begin
    DB.execute("INSERT INTO users (username, password, role) VALUES (?, ?, ?)",
               [params[:username], params[:password], params[:role]])
    redirect '/login'
  rescue SQLite3::ConstraintException
    @error = "Username already taken! Choose another."
    erb :signup
  end
end

get '/logout' do
  session.clear
  redirect '/'
end

# --- APP ROUTES ---

# Only posting items requires login now. Home page (/) is public!
before do
  if request.path_info == '/items/new' && !session[:user_id]
    redirect '/login'
  end
end

# PUBLIC HOME PAGE
get '/' do
  category = params[:category]
  search = params[:search]

  query = "SELECT items.*, users.username FROM items JOIN users ON items.user_id = users.id WHERE 1=1"
  args = []

  if category && !category.empty?
    query += " AND items.category = ?"
    args << category
  end

  if search && !search.empty?
    query += " AND (items.title LIKE ? OR items.description LIKE ?)"
    args << "%#{search}%"
    args << "%#{search}%"
  end

  query += " ORDER BY items.id DESC"
  @items = DB.execute(query, args)
  @selected_category = category
  @search_query = search

  erb :index
end

get '/items/new' do
  erb :new
end

# CREATE ITEM WITH FILE UPLOAD
post '/items' do
  redirect '/login' unless session[:user_id]

  image_path = "/images/no-image.png"

  if params[:image] && params[:image][:filename]
    filename = params[:image][:filename]
    file = params[:image][:tempfile]
    target_path = File.join(UPLOAD_DIR, filename)

    File.open(target_path, 'wb') do |f|
      f.write(file.read)
    end
    image_path = "/uploads/#{filename}"
  end

  DB.execute(
    "INSERT INTO items (title, category, location, description, image_path, contact, user_id, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    [
      params[:title],
      params[:category],
      params[:location],
      params[:description],
      image_path,
      params[:contact],
      session[:user_id],
      params[:status]
    ]
  )
  redirect '/'
end

# EDIT ITEM ROUTES
get '/items/:id/edit' do
  redirect '/login' unless session[:user_id]
  @item = DB.execute("SELECT * FROM items WHERE id = ?", [params[:id]]).first
  if @item && (session[:role] == 'Admin' || @item['user_id'] == session[:user_id])
    erb :edit
  else
    redirect '/'
  end
end

post '/items/:id/update' do
  redirect '/login' unless session[:user_id]
  item = DB.execute("SELECT * FROM items WHERE id = ?", [params[:id]]).first
  if item && (session[:role] == 'Admin' || item['user_id'] == session[:user_id])
    image_path = item['image_path']

    if params[:image] && params[:image][:filename] && !params[:image][:filename].empty?
      filename = params[:image][:filename]
      file = params[:image][:tempfile]
      target_path = File.join(UPLOAD_DIR, filename)

      File.open(target_path, 'wb') do |f|
        f.write(file.read)
      end
      image_path = "/uploads/#{filename}"
    end

    DB.execute(
      "UPDATE items SET title = ?, category = ?, location = ?, description = ?, image_path = ?, contact = ?, status = ? WHERE id = ?",
      [
        params[:title],
        params[:category],
        params[:location],
        params[:description],
        image_path,
        params[:contact],
        params[:status],
        params[:id]
      ]
    )
  end
  redirect '/'
end

post '/items/:id/claim' do
  redirect '/login' unless session[:user_id]
  if ['Teacher', 'Admin'].include?(session[:role])
    item = DB.execute("SELECT * FROM items WHERE id = ?", [params[:id]]).first
    if item
      new_status = (item['status'] == 'Claimed') ? 'Lost' : 'Claimed'
      DB.execute("UPDATE items SET status = ? WHERE id = ?", [new_status, params[:id]])
    end
  end
  redirect '/'
end

post '/items/:id/delete' do
  redirect '/login' unless session[:user_id]
  if session[:role] == 'Admin'
    DB.execute("DELETE FROM items WHERE id = ?", [params[:id]])
  end
  redirect '/'
end

__END__

@@ layout
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>School Lost & Found Portal</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css">
</head>
<body class="bg-light">
  <nav class="navbar navbar-dark bg-dark mb-4 shadow-sm">
    <div class="container">
      <a class="navbar-brand fw-bold" href="/">🔍 School Lost & Found</a>
      <div class="d-flex align-items-center gap-3">
        <% if session[:user_id] %>
          <span class="text-light small">User: <strong><%= session[:username] %></strong>
            <span class="badge bg-<%= session[:role] == 'Admin' ? 'danger' : (session[:role] == 'Teacher' ? 'warning text-dark' : 'info text-dark') %>">
              <%= session[:role] %>
            </span>
          </span>
          <a href="/items/new" class="btn btn-warning btn-sm fw-bold">+ Report Item</a>
          <a href="/logout" class="btn btn-outline-light btn-sm">Logout</a>
        <% else %>
          <a href="/login" class="btn btn-outline-light btn-sm">Login</a>
          <a href="/signup" class="btn btn-warning btn-sm fw-bold">Sign Up</a>
        <% end %>
      </div>
    </div>
  </nav>

  <div class="container pb-5">
    <%= yield %>
  </div>
</body>
</html>

@@ login
<div class="row justify-content-center mt-5">
  <div class="col-md-4">
    <div class="card shadow-sm border-0 p-4 bg-white">
      <h3 class="mb-3 text-center">Portal Login</h3>
      <% if @error %>
        <div class="alert alert-danger py-2"><%= @error %></div>
      <% end %>
      <form action="/login" method="POST">
        <div class="mb-3">
          <label class="form-label">Username</label>
          <input type="text" name="username" class="form-control" required>
        </div>
        <div class="mb-3">
          <label class="form-label">Password</label>
          <input type="password" name="password" class="form-control" required>
        </div>
        <button type="submit" class="btn btn-dark w-100 mb-3">Login</button>
      </form>
      <p class="text-center small mb-0">Don't have an account? <a href="/signup">Sign up</a></p>
      <hr class="my-3">
      
    </div>
  </div>
</div>

@@ signup
<div class="row justify-content-center mt-5">
  <div class="col-md-4">
    <div class="card shadow-sm border-0 p-4 bg-white">
      <h3 class="mb-3 text-center">Create Account</h3>
      <% if @error %>
        <div class="alert alert-danger py-2"><%= @error %></div>
      <% end %>
      <form action="/signup" method="POST">
        <div class="mb-3">
          <label class="form-label">Username</label>
          <input type="text" name="username" class="form-control" required>
        </div>
        <div class="mb-3">
          <label class="form-label">Password</label>
          <input type="password" name="password" class="form-control" required>
        </div>
        <div class="mb-3">
          <label class="form-label">Select Role</label>
          <select name="role" class="form-select" required>
            <option value="Student">Student</option>
            <option value="Teacher">Teacher</option>
            <option value="Admin">Admin</option>
          </select>
        </div>
        <button type="submit" class="btn btn-dark w-100 mb-3">Sign Up</button>
      </form>
      <p class="text-center small mb-0">Already have an account? <a href="/login">Login</a></p>
    </div>
  </div>
</div>

@@ index
<div class="row mb-4 align-items-center">
  <div class="col-md-6">
    <h2>Campus Lost & Found</h2>
    <% if session[:user_id] %>
      <p class="text-muted">Welcome back, <strong><%= session[:username] %></strong>!</p>
    <% else %>
      <p class="text-muted">Public Notice Board. <a href="/login">Login</a> or <a href="/signup">Sign up</a> to report items.</p>
    <% end %>
  </div>
  <div class="col-md-6">
    <form action="/" method="GET" class="row g-2">
      <div class="col-7">
        <input type="text" name="search" class="form-control" placeholder="Search keywords..." value="<%= @search_query %>">
      </div>
      <div class="col-3">
        <select name="category" class="form-select" onchange="this.form.submit()">
          <option value="">All Categories</option>
          <option value="Electronics" <%= 'selected' if @selected_category == 'Electronics' %>>Electronics</option>
          <option value="Books" <%= 'selected' if @selected_category == 'Books' %>>Books</option>
          <option value="Clothing" <%= 'selected' if @selected_category == 'Clothing' %>>Clothing</option>
          <option value="Stationery" <%= 'selected' if @selected_category == 'Stationery' %>>Stationery</option>
          <option value="Other" <%= 'selected' if @selected_category == 'Other' %>>Other</option>
        </select>
      </div>
      <div class="col-2">
        <button type="submit" class="btn btn-secondary w-100">Filter</button>
      </div>
    </form>
  </div>
</div>

<div class="row">
  <% @items.each do |item| %>
    <div class="col-md-4 mb-3">
      <div class="card h-100 shadow-sm border-0">
        <img src="<%= item['image_path'] %>" class="card-img-top" alt="Item Image" style="height: 180px; object-fit: cover;" onerror="this.src='https://via.placeholder.com/400x200?text=No+Image'">
        <div class="card-body">
          <div class="d-flex justify-content-between align-items-start mb-2">
            <h5 class="card-title fw-bold text-dark mb-0"><%= item['title'] %></h5>
            <% if item['status'] == 'Lost' %>
              <span class="badge bg-danger">Lost</span>
            <% elsif item['status'] == 'Found' %>
              <span class="badge bg-success">Found</span>
            <% else %>
              <span class="badge bg-secondary">Claimed</span>
            <% end %>
          </div>

          <h6 class="text-muted small mb-2">Category: <strong><%= item['category'] %></strong></h6>
          <p class="text-muted small mb-2">Posted by: <strong><%= item['username'] %></strong></p>

          <p class="card-text mb-1"><strong>📍 Location:</strong> <%= item['location'] %></p>
          <p class="card-text mb-2"><strong>📝 Details:</strong> <%= item['description'] %></p>
          <p class="card-text small text-primary mb-3"><strong>📞 Contact:</strong> <%= item['contact'] %></p>

          <% if session[:user_id] %>
            <div class="d-flex gap-2 flex-wrap">
              <% if session[:role] == 'Admin' || item['user_id'] == session[:user_id] %>
                <a href="/items/<%= item['id'] %>/edit" class="btn btn-outline-secondary btn-sm">Edit</a>
              <% end %>

              <% if ['Teacher', 'Admin'].include?(session[:role]) %>
                <form action="/items/<%= item['id'] %>/claim" method="POST" class="flex-grow-1">
                  <button type="submit" class="btn btn-outline-<%= item['status'] == 'Claimed' ? 'dark' : 'success' %> btn-sm w-100">
                    <%= item['status'] == 'Claimed' ? 'Reopen' : 'Verify Claim' %>
                  </button>
                </form>
              <% end %>

              <% if session[:role] == 'Admin' %>
                <form action="/items/<%= item['id'] %>/delete" method="POST">
                  <button type="submit" class="btn btn-outline-danger btn-sm" onclick="return confirm('Delete this record?')">Delete</button>
                </form>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  <% end %>

  <% if @items.empty? %>
    <div class="col-12 text-center py-5">
      <p class="text-muted fs-5">No items found matching your criteria.</p>
    </div>
  <% end %>
</div>

@@ new
<div class="row justify-content-center">
  <div class="col-md-6">
    <div class="card shadow-sm border-0 p-4 bg-white">
      <h3 class="mb-3">Report Lost or Found Item</h3>

      <form action="/items" method="POST" enctype="multipart/form-data">
        <div class="mb-3">
          <label class="form-label">Item Title</label>
          <input type="text" name="title" class="form-control" placeholder="e.g., Casio Calculator, Water Bottle" required>
        </div>

        <div class="mb-3">
          <label class="form-label">Status Type</label>
          <select name="status" class="form-select" required>
            <option value="Lost">I Lost This Item</option>
            <option value="Found">I Found This Item</option>
          </select>
        </div>

        <div class="mb-3">
          <label class="form-label">Category</label>
          <select name="category" class="form-select" required>
            <option value="Electronics">Electronics</option>
            <option value="Books">Books & Notebooks</option>
            <option value="Clothing">Clothing & Uniform</option>
            <option value="Stationery">Stationery</option>
            <option value="Other">Other</option>
          </select>
        </div>

        <div class="mb-3">
          <label class="form-label">Location</label>
          <input type="text" name="location" class="form-control" placeholder="e.g., Room 204, Canteen, Lab" required>
        </div>

        <div class="mb-3">
          <label class="form-label">Upload Photo (From Gallery or Camera)</label>
          <input type="file" name="image" class="form-control" accept="image/*">
        </div>

        <div class="mb-3">
          <label class="form-label">Description</label>
          <textarea name="description" class="form-control" rows="3" placeholder="Color, brand name, unique marks..."></textarea>
        </div>

        <div class="mb-3">
          <label class="form-label">Contact Info / Class</label>
          <input type="text" name="contact" class="form-control" placeholder="e.g., Rahul Sharma (Class 12-A)" required>
        </div>

        <div class="d-flex justify-content-between">
          <a href="/" class="btn btn-secondary">Cancel</a>
          <button type="submit" class="btn btn-dark">Submit Report</button>
        </div>
      </form>
    </div>
  </div>
</div>

@@ edit
<div class="row justify-content-center">
  <div class="col-md-6">
    <div class="card shadow-sm border-0 p-4 bg-white">
      <h3 class="mb-3">Edit Item Listing</h3>

      <form action="/items/<%= @item['id'] %>/update" method="POST" enctype="multipart/form-data">
        <div class="mb-3">
          <label class="form-label">Item Title</label>
          <input type="text" name="title" class="form-control" value="<%= @item['title'] %>" required>
        </div>

        <div class="mb-3">
          <label class="form-label">Status Type</label>
          <select name="status" class="form-select" required>
            <option value="Lost" <%= 'selected' if @item['status'] == 'Lost' %>>Lost</option>
            <option value="Found" <%= 'selected' if @item['status'] == 'Found' %>>Found</option>
            <option value="Claimed" <%= 'selected' if @item['status'] == 'Claimed' %>>Claimed</option>
          </select>
        </div>

        <div class="mb-3">
          <label class="form-label">Category</label>
          <select name="category" class="form-select" required>
            <option value="Electronics" <%= 'selected' if @item['category'] == 'Electronics' %>>Electronics</option>
            <option value="Books" <%= 'selected' if @item['category'] == 'Books' %>>Books & Notebooks</option>
            <option value="Clothing" <%= 'selected' if @item['category'] == 'Clothing' %>>Clothing & Uniform</option>
            <option value="Stationery" <%= 'selected' if @item['category'] == 'Stationery' %>>Stationery</option>
            <option value="Other" <%= 'selected' if @item['category'] == 'Other' %>>Other</option>
          </select>
        </div>

        <div class="mb-3">
          <label class="form-label">Location</label>
          <input type="text" name="location" class="form-control" value="<%= @item['location'] %>" required>
        </div>

        <div class="mb-3">
          <label class="form-label">Change Photo (Optional)</label>
          <input type="file" name="image" class="form-control" accept="image/*">
        </div>

        <div class="mb-3">
          <label class="form-label">Description</label>
          <textarea name="description" class="form-control" rows="3"><%= @item['description'] %></textarea>
        </div>

        <div class="mb-3">
          <label class="form-label">Contact Info / Class</label>
          <input type="text" name="contact" class="form-control" value="<%= @item['contact'] %>" required>
        </div>

        <div class="d-flex justify-content-between">
          <a href="/" class="btn btn-secondary">Cancel</a>
          <button type="submit" class="btn btn-dark">Update Listing</button>
        </div>
      </form>
    </div>
  </div>
</div>

set :port, ENV['PORT'] if ENV['PORT']
set :bind, '0.0.0.0'