class RestoreSettings
  unloadable

  include UseCaseBase

  attr_reader :old_valuehash
  attr_reader :valuehash

  attr_reader :resync_projects
  attr_reader :resync_ssh_keys
  attr_reader :flush_cache


  def initialize(old_valuehash, valuehash, opts = {})
    @old_valuehash     = old_valuehash
    @valuehash         = valuehash

    @resync_projects   = opts.delete(:resync_projects){ false }
    @resync_ssh_keys   = opts.delete(:resync_ssh_keys){ false }
    @flush_cache       = opts.delete(:flush_cache){ false }
    @delete_trash_repo = opts.delete(:delete_trash_repo){ [] }

    super
  end


  def call
    restore_settings
    super
  end


  private


    def restore_settings
      check_repo_hierarchy
      check_gitolite_config
      check_gitolite_default_values
      check_hook_install
      check_hook_config
      check_cache_config
      do_resync_projects
      do_resync_ssh_keys
      do_flush_cache
    end


    def check_repo_hierarchy
      ## Storage infos has changed, move repositories!
      if old_valuehash[:gitolite_global_storage_dir]  != valuehash[:gitolite_global_storage_dir]  ||
         old_valuehash[:gitolite_redmine_storage_dir] != valuehash[:gitolite_redmine_storage_dir] ||
         old_valuehash[:hierarchical_organisation]    != valuehash[:hierarchical_organisation]

        # Need to update everyone!
        # We take all root projects (even those who are closed) and move each hierarchy individually
        projects = Project.includes(:repositories).all.select { |x| x if x.parent_id.nil? }
        if projects.length > 0
          RedmineGitolite::GitHosting.logger.info { "Gitolite configuration has been modified : repositories hierarchy" }
          RedmineGitolite::GitHosting.logger.info { "Resync all projects (root projects : '#{projects.length}')..." }
          RedmineGitolite::GitHosting.resync_gitolite(:move_repositories_tree, projects.length, {:flush_cache => true})
        end
      end
    end


    def check_gitolite_config
      ## Gitolite config file has changed, create a new one!
      if old_valuehash[:gitolite_config_file] != valuehash[:gitolite_config_file] ||
         old_valuehash[:gitolite_config_has_admin_key] != valuehash[:gitolite_config_has_admin_key]

        RedmineGitolite::GitHosting.logger.info { "Gitolite configuration has been modified, resync all projects (active, closed, archived)..." }
        RedmineGitolite::GitHosting.resync_gitolite(:update_projects, 'all')
      end
    end


    def check_gitolite_default_values
      ## Gitolite default values has changed, update active projects
      if old_valuehash[:gitolite_notify_global_prefix]         != valuehash[:gitolite_notify_global_prefix]         ||
         old_valuehash[:gitolite_notify_global_sender_address] != valuehash[:gitolite_notify_global_sender_address] ||
         old_valuehash[:gitolite_notify_global_include]        != valuehash[:gitolite_notify_global_include]        ||
         old_valuehash[:gitolite_notify_global_exclude]        != valuehash[:gitolite_notify_global_exclude]

        RedmineGitolite::GitHosting.logger.info { "Gitolite configuration has been modified, resync all active projects..." }
        RedmineGitolite::GitHosting.resync_gitolite(:update_projects, 'active')
      end
    end


    def check_hook_install
      ## Gitolite user has changed, check if this new one has our hooks!
      if old_valuehash[:gitolite_user] != valuehash[:gitolite_user]
        hooks = RedmineGitolite::Hooks.new
        hooks.check_install
      end
    end


    def check_hook_config
      ## Gitolite hooks config has changed, update our .gitconfig!
      if old_valuehash[:gitolite_hooks_debug]            != valuehash[:gitolite_hooks_debug]        ||
         old_valuehash[:gitolite_force_hooks_update]     != valuehash[:gitolite_force_hooks_update] ||
         old_valuehash[:gitolite_hooks_are_asynchronous] != valuehash[:gitolite_hooks_are_asynchronous]

        # Need to update our .gitconfig
        hooks = RedmineGitolite::Hooks.new
        hooks.hook_params_installed?
      end
    end


    def check_cache_config
      ## Gitolite cache has changed, clear cache entries!
      if old_valuehash[:gitolite_cache_max_time] != valuehash[:gitolite_cache_max_time]
        RedmineGitolite::Cache.clear_obsolete_cache_entries
      end
    end


    def do_resync_projects
      ## A resync has been asked within the interface, update all projects in force mode
      if resync_projects
        RedmineGitolite::GitHosting.logger.info { "Forced resync of all projects (active, closed, archived)..." }
        RedmineGitolite::GitHosting.resync_gitolite(:update_projects, 'all', {:force => true})
      end
    end


    def do_resync_ssh_keys
      ## A resync has been asked within the interface, update all projects in force mode
      if resync_ssh_keys
        RedmineGitolite::GitHosting.logger.info { "Forced resync of all ssh keys..." }
        RedmineGitolite::GitHosting.resync_gitolite(:resync_all_ssh_keys, 'all')
      end
    end


    def do_flush_cache
      ## A cache flush has been asked within the interface
      if flush_cache
        RedmineGitolite::GitHosting.logger.info { "Flush Git Cache" }
        ActiveRecord::Base.connection.execute("TRUNCATE git_caches")
      end
    end


    def do_delete_trash_repo
      if !delete_trash_repo.empty?
        RedmineGitolite::GitHosting.resync_gitolite(:purge_recycle_bin, delete_trash_repo)
      end
    end

end
