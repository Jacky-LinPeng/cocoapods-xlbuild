require_relative 'rome/build_framework'
require_relative 'helper/passer'
require_relative 'helper/target_checker'


# patch prebuild ability
module Pod
    class Installer

        
        private

        def local_manifest 
            if not @local_manifest_inited
                @local_manifest_inited = true
                raise "This method should be call before generate project" unless self.analysis_result == nil
                @local_manifest = self.sandbox.manifest
            end
            @local_manifest
        end

        # @return [Analyzer::SpecsState]
        def prebuild_pods_changes
            return nil if local_manifest.nil?
            if @prebuild_pods_changes.nil?
                changes = local_manifest.detect_changes_with_podfile(podfile)
                @prebuild_pods_changes = Analyzer::SpecsState.new(changes)
                # save the chagnes info for later stage
                Pod::Prebuild::Passer.prebuild_pods_changes = @prebuild_pods_changes 
            end
            @prebuild_pods_changes
        end

        
        public 

        # check if need to prebuild
        def have_exact_prebuild_cache?
            # check if need build frameworks
            return false if local_manifest == nil
            
            changes = prebuild_pods_changes
            added = changes.added
            changed = changes.changed 
            unchanged = changes.unchanged
            deleted = changes.deleted 
            
            exsited_framework_pod_names = sandbox.exsited_framework_pod_names
            missing = unchanged.select do |pod_name|
                not exsited_framework_pod_names.include?(pod_name)
            end

            needed = (added + changed + deleted + missing)
            return needed.empty?
        end
        
        
        # The install method when have completed cache
        def install_when_cache_hit!
            # just print log
            self.sandbox.exsited_framework_target_names.each do |name|
                UI.puts "Using #{name}"
            end
        end

        # Build the needed framework files
        def prebuild_frameworks! 
            # build options
            sandbox_path = sandbox.root
            existed_framework_folder = sandbox.generate_framework_path
            bitcode_enabled = Pod::Podfile::DSL.bitcode_enabled
            use_static_framework = Pod::Podfile::DSL.static_binary
            targets = []
            
            if local_manifest != nil
                changes = prebuild_pods_changes
                added = changes.added
                changed = changes.changed 
                unchanged = changes.unchanged
                deleted = changes.deleted 
    
                existed_framework_folder.mkdir unless existed_framework_folder.exist?
                exsited_framework_pod_names = sandbox.exsited_framework_pod_names
    
                # additions
                missing = unchanged.select do |pod_name|
                    not exsited_framework_pod_names.include?(pod_name)
                end
                root_names_to_update = (added + changed + missing).uniq
                # 生成预编译target
                cache = []
                targets = root_names_to_update.map do |pod_name|
                    tars = Pod.fast_get_targets_for_pod_name(pod_name, self.pod_targets, cache)
                    if tars.nil?
                        tars = []
                    end
                    tars
                end.flatten

                # 添加依赖
                dependency_targets = targets.map {|t| t.recursive_dependent_targets }.flatten.uniq || []
                dependency_targets = dependency_targets.select do |tar|
                    sandbox.existed_target_version_for_pod_name(tar.pod_name) != tar.version
                end
                targets = (targets + dependency_targets).uniq
            else
                targets = self.pod_targets
            end

            targets = targets.reject {|pod_target| sandbox.local?(pod_target.pod_name) }

            
            # build!
            Pod::UI.puts "Prebuild frameworks (total #{targets.count})"
            Pod::Prebuild.remove_build_dir(sandbox_path)
            targets.each do |target|
                #linpeng edit  + target.version
                @sandbox_framework_folder_path_for_target_name = sandbox.framework_folder_path_for_target_name(target.name)
                output_path = @sandbox_framework_folder_path_for_target_name
                output_path.rmtree if output_path.exist?
                if !target.should_build?
                    UI.puts "Prebuilding #{target.label}"
                    next
                end
                output_path.mkpath unless output_path.exist?

                #local cache
                localCachePathRoot = Pod::Podfile::DSL.local_frameworks_cache_path
                is_static_binary = Pod::Podfile::DSL.static_binary
                type_frameworks_dir = is_static_binary ? "static" : "dynamic"
                is_has_local_cache = localCachePathRoot != nil
                if not is_has_local_cache
                    #开始使用XcodeBuild进行编译静态库
                    Pod::Prebuild.build(sandbox_path, target, output_path, bitcode_enabled,  Podfile::DSL.custom_build_options,  Podfile::DSL.custom_build_options_simulator)
                else
                    targetFrameworkPath = localCachePathRoot + "/#{type_frameworks_dir}/#{target.name}/#{target.version}"
                    if Dir.exist?(targetFrameworkPath)
                        puts "[XL].本地缓存仓库获取:#{target.name}（#{target.version}） #{type_frameworks_dir}"
                        Dir.foreach(targetFrameworkPath) do |file|
                            if file !="." and file !=".."
                                f = targetFrameworkPath+"/"+file
                                FileUtils.cp_r(f, output_path, :remove_destination => false )
                            end
                        end
                    else
                        #开始使用XcodeBuild进行编译静态库
                        Pod::Prebuild.build(sandbox_path, target, output_path, bitcode_enabled,  Podfile::DSL.custom_build_options,  Podfile::DSL.custom_build_options_simulator)

                        #save for cache
                        puts "[XL].本地缓存仓库新增:#{target.name}（#{target.version} #{type_frameworks_dir}"
                        local_cache_path = targetFrameworkPath
                        FileUtils.makedirs(local_cache_path) unless File.exists?local_cache_path
                        c_output_path = output_path.to_s
                        if Dir.exist?(output_path)
                            Dir.foreach(output_path) do |file|
                                if file !="." and file !=".."
                                    f = c_output_path+"/"+file
                                    FileUtils.cp_r(f, local_cache_path, :remove_destination => false )
                                end
                            end
                        end
                    end
                end

                # save the resource paths for later installing，动态库需要将frameworkwork中资源链接到pod上
                if target.static_framework? and !target.resource_paths.empty?
                    framework_path = output_path + target.framework_name
                    standard_sandbox_path = sandbox.standard_sanbox_path

                    resources = begin
                        if Pod::VERSION.start_with? "1.5"
                            target.resource_paths
                        else
                            # resource_paths is Hash{String=>Array<String>} on 1.6 and above
                            # (use AFNetworking to generate a demo data)
                            # https://github.com/leavez/cocoapods-binary/issues/50
                            target.resource_paths.values.flatten
                        end
                    end
                    raise "Wrong type: #{resources}" unless resources.kind_of? Array
                    path_objects = resources.map do |path|
                        object = Prebuild::Passer::ResourcePath.new
                        object.real_file_path = framework_path + File.basename(path)
                        # 静态库资源目录处理
                        if use_static_framework
                            object.real_file_path = path.gsub('${PODS_ROOT}', existed_framework_folder.to_s) if path.start_with? '${PODS_ROOT}'
                            object.real_file_path = path.gsub("${PODS_CONFIGURATION_BUILD_DIR}", existed_framework_folder.to_s) if path.start_with? "${PODS_CONFIGURATION_BUILD_DIR}"
                            real_bundle_path = path.gsub('${PODS_ROOT}', sandbox_path.to_s) if path.start_with? '${PODS_ROOT}'
                            real_bundle_path = path.gsub('${PODS_CONFIGURATION_BUILD_DIR}', sandbox_path.to_s) if path.start_with? '${PODS_CONFIGURATION_BUILD_DIR}'
                            real_origin_path = Pathname.new(real_bundle_path)
                            real_file_path_obj = Pathname.new(object.real_file_path)
                            if real_origin_path.exist?
                                real_file_path_obj.parent.mkpath unless real_file_path_obj.parent.exist?
                                FileUtils.cp_r(real_origin_path, real_file_path_obj, :remove_destination => true)
                            end
                        end
                        object.target_file_path = path.gsub('${PODS_ROOT}', standard_sandbox_path.to_s) if path.start_with? '${PODS_ROOT}'
                        object.target_file_path = path.gsub("${PODS_CONFIGURATION_BUILD_DIR}", standard_sandbox_path.to_s) if path.start_with? "${PODS_CONFIGURATION_BUILD_DIR}"
                        object
                    end
                    Prebuild::Passer.resources_to_copy_for_static_framework[target.name] = path_objects
                end
            end
            Pod::Prebuild.remove_build_dir(sandbox_path)

            # copy vendored libraries and frameworks
            targets.each do |target|
                root_path = self.sandbox.pod_dir(target.name)
                target_folder = sandbox.framework_folder_path_for_target_name(target.name)
                
                # If target shouldn't build, we copy all the original files
                # This is for target with only .a and .h files
                if not target.should_build? 
                    Prebuild::Passer.target_names_to_skip_integration_framework << target.name
                    FileUtils.cp_r(root_path, target_folder, :remove_destination => true)
                    next
                end

                target.spec_consumers.each do |consumer|
                    file_accessor = Sandbox::FileAccessor.new(root_path, consumer)
                    lib_paths = file_accessor.vendored_frameworks || []
                    lib_paths += file_accessor.vendored_libraries
                    # @TODO dSYM files
                    lib_paths.each do |lib_path|
                        relative = lib_path.relative_path_from(root_path)
                        destination = target_folder + relative
                        destination.dirname.mkpath unless destination.dirname.exist?
                        FileUtils.cp_r(lib_path, destination, :remove_destination => true)
                    end
                end
            end

            # save the pod_name for prebuild framwork in sandbox 
            targets.each do |target|
                sandbox.save_pod_name_for_target target
            end
            
            # Remove useless files
            # remove useless pods
            all_needed_names = self.pod_targets.map(&:name).uniq
            useless_target_names = sandbox.exsited_framework_target_names.reject do |name| 
                all_needed_names.include? name
            end
            useless_target_names.each do |name|
                path = sandbox.framework_folder_path_for_target_name(name)
                path.rmtree if path.exist?
            end

            if Podfile::DSL.dont_remove_source_code 
                 # just remove the tmp files
                path = sandbox.root + 'Manifest.lock.tmp'
                path.rmtree if path.exist?
            else 
               # only keep manifest.lock and framework folder in _Prebuild
                to_remain_files = ["Manifest.lock", File.basename(existed_framework_folder)]
                to_delete_files = sandbox_path.children.select do |file|
                    filename = File.basename(file)
                    not to_remain_files.include?(filename)
                end
                to_delete_files.each do |path|
                    path.rmtree if path.exist?
                end
            end
        end

        # hook run_plugins_post_install_hooks 方法
        install_hooks_method = instance_method(:run_plugins_post_install_hooks)
        define_method(:run_plugins_post_install_hooks) do
            install_hooks_method.bind(self).()
            if Pod::is_prebuild_stage
                #开始编译
                self.prebuild_frameworks!
            end
        end
    end
end