lock '3.9.1'

set :application, 'chemotion'
set :repo_url, 'git@github.com:ComPlat/chemotion_ELN.git'

# Default branch is :master
ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

set :deploy_to, '/home/deploy/www/chemotion'

set :rails_env, 'production'
set :unicorn_env, 'production'
set :unicorn_rack_env, 'production'
set :whenever_identifier, -> { "#{fetch(:application)}_#{fetch(:stage)}" }
set :bundle_jobs, 4 # parallel bundler

set :nvm_type, :user
set :nvm_node, File.exist?('.nvmrc') && File.read('.nvmrc').strip || 'v12.22.1'
set :npm_version, File.exist?('.npm-version') && File.read('.npm-version').strip || '7.11.1'
set :nvm_map_bins, fetch(:nvm_map_bins, []).push('rake')
set :nvm_map_bins, fetch(:nvm_map_bins, []).push('bundle')
# Default value for :format is :pretty
# set :format, :pretty

# Default value for :log_level is :debug
# set :log_level, :debug
set :format_options, command_output: true
set :log_file, 'log/capistrano.log'

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
set :linked_files, fetch(:linked_files, []).push(
  'config/database.yml',
  'config/storage.yml',
  'config/user_props.yml',
  # 'config/datacollectors.yml',
  'config/secrets.yml',
  # 'config/spectra.yml',
  '.env'
)

# Default value for linked_dirs is []
set :linked_dirs, fetch(:linked_dirs, []).push(
  'backup/deploy_backup', 'backup/weekly_backup',
  'node_modules',
  'log',
  'public/images', 'public/docx', 'public/simulations', 'public/zip',
  'tmp/pids', 'tmp/cache', 'tmp/sockets', 'tmp/uploads',
  'uploads'
)

version = File.readlines('.ruby-version')[0].strip if File.exist?('.ruby-version')
gemset = File.readlines('.ruby-gemset')[0].strip if File.exist?('.ruby-gemset')

set(:rvm_ruby_version, "#{version}#{'@' if gemset}#{gemset}") if File.exist?('.ruby-version')

set :slackistrano, false

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
# set :keep_releases, 5

# before 'deploy:migrate', 'deploy:backup'

## NMV and NPM tasks
## Install node version if not installed
before 'nvm:validate', 'deploy:nvm_check'
## Install defined version of npm if not selected
before 'nvm:validate', 'deploy:npm_install_npm'
## Clear all npm packages
before 'npm:install', 'deploy:clear_node_module'

after 'deploy:publishing', 'deploy:restart'

namespace :git do
  task :update_repo_url do
    on roles(:all) do
      within repo_path do
        execute :git, 'remote', 'set-url', 'origin', fetch(:repo_url)
      end
    end
  end
end

namespace :deploy do
  task :backup do
    server_name = ''
    on roles :app do |server|
      server_name = server.hostname
      within "#{fetch(:deploy_to)}/current/" do
        with RAILS_ENV: fetch(:rails_env) do
          execute :bundle, 'exec backup perform -t deploy_backup -c backup/config.rb'
        end
      end
    end

    # RSync local folder with server backups
    backup_dir = "#{fetch(:user)}@#{server_name}:#{fetch(:deploy_to)}/shared/backup"
    unless system("rsync -r #{backup_dir}/deploy_backup backup")
      raise 'Error while sync backup folder'
    end
  end

  task :nvm_check do
    on roles :app do
      execute <<~SH
        source "#{fetch(:nvm_path)}/nvm.sh" && [[ $(nvm version #{fetch(:nvm_node)}) != "#{fetch(:nvm_node)}" ]] && nvm install #{fetch(:nvm_node)}; nvm use #{fetch(:nvm_node)}
      SH
    end
  end

  task :npm_install_npm do
    on roles :app do
      execute <<~SH
        source "#{fetch(:nvm_path)}/nvm.sh" && nvm use #{fetch(:nvm_node)} && [[ $(npm -v npm) == "#{fetch(:npm_version)}" ]] && echo "npm already installed" || npm install -g npm@#{fetch(:npm_version)}
      SH
      # source "#{fetch(:nvm_path)}/nvm.sh" && nvm use #{fetch(:nvm_node)} && [[ $(npm -v npm) == $(cat .npm-version) ]] && echo "npm already installed" ||  npm install -g npm
    end
  end

  task :clear_node_module do
    on roles :app do
      execute "find  #{fetch(:deploy_to)}/shared/node_modules/. -name . -o -prune -exec rm -rf -- {} +"
    end
  end

  task :restart do
    on roles :app do
      execute :touch, "#{current_path}/tmp/restart.txt"
    end
  end

  after :restart, :clear_cache do
    on roles :app do
      # Here we can do anything such as:
      within release_path do
        with RAILS_ENV: fetch(:rails_env) do
          execute :rake, 'tmp:cache:clear'
        end
      end
    end
  end

  task :restart do
    on roles :app do
      invoke 'delayed_job:restart'
    end
  end
end

namespace :delayed_job do
  def args
    fetch(:delayed_job_args, '')
  end

  def delayed_job_roles
    fetch(:delayed_job_server_role, :app)
  end

  desc 'Stop the delayed_job process'
  task :stop do
    on roles(delayed_job_roles) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, :exec, :'bin/delayed_job', :stop
        end
      end
    end
  end

  desc 'Start the delayed_job process'
  task :start do
    on roles(delayed_job_roles) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, :exec, :'bin/delayed_job', args, :start
        end
      end
    end
  end

  desc 'Restart the delayed_job process'
  task :restart do
    on roles(delayed_job_roles) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, :exec, :'bin/delayed_job', args, :restart
        end
      end
    end
  end
end
