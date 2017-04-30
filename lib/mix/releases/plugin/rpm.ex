defmodule Mix.Releases.Plugin.Rpm do
  use Mix.Releases.Plugin

  @_SPEC                "spec"
  @_INIT_FILE           "init_script"
  @_RPM_DIR             "rpm"
  @_DEFAULT_BUILD_ARCH  "x86_64"
  @_RPM_BUILD_TOOL      "/usr/bin/rpmbuild"
  @_RPM_BUILD_ARGS      "-bb"
  @_DEFAULT_SUMMARY     "Add a summary entry in your project config"
  @_DEFAULT_DESCRIPTION "Add a description your config file"
  @_RPM_TEMPLATE_DIR    Path.join([@_RPM_DIR, "templates"])
  @_EXTRA_SOURCES       Path.join([@_RPM_DIR, "sources"])

  @_RPM_SPEC_DIRS  [
    ["SPECS"],
    ["SOURCES"],
    ["RPMS"],
    ["SRPMS"],
    ["BUILD"]
  ]

  @_NAME        "{{{PROJECT_NAME}}}"
  @_VERSION     "{{{PROJECT_VERSION}}}"
  @_RELEASE     "{{{PROJECT_RELEASE}}}"
  @_TOPDIR      "{{{PROJECT_TOPDIR}}}"
  @_BUILD_ARCH  "{{{BUILD_ARCHITECTURE}}}"
  @_SUMMARY     "{{{SUMMARY}}}"
  @_DESCRIPTION "{{{DESCRIPTION}}}"

  def before_assembly(release, _opts), do: release
  def before_package(release, _opts), do:  release

  def after_package(release, _opts) do
    release
    |> do_config
    |> do_spec
    |> do_init_script
    |> copy_extra_sources
    |> create_rpm
  end

  def after_assembly(release, _), do:  release

  def after_cleanup(_args, _opts) do
    build_dir = build_dir()
    if File.exists?(build_dir) do
      File.rm_rf!(build_dir)
      debug "Removed rpm build files..."
    end

    :ok
  end

  defp rpm_dir do
    build_dir() |> Path.join("rpm")
  end

  defp build_dir do
    Mix.Project.build_path()
  end

  defp do_config(%Release{name: name, version: version} = config) do
    app_archive = "#{name}-#{version}.tar.gz"

    build_dir   = get_config_item(config, :build_dir,   build_dir())
    rpm_dir     = get_config_item(config, :rpm_dir,     rpm_dir())
    build_arch  = get_config_item(config, :build_arch,  @_DEFAULT_BUILD_ARCH)

    config
    |> Map.merge(%{
      app_archive:     app_archive,
      build_dir:       build_dir,
      rpm_dir:         rpm_dir,
      build_arch:      build_arch
    })
    |> Map.merge(
      (for {item, default} <- [
        rpmbuild:        @_RPM_BUILD_TOOL,
        rpmbuild_opts:   @_RPM_BUILD_ARGS,
        priv_path:       Path.join([__DIR__, "..", "..", "priv"]) |> Path.expand,
        sources_path:    Path.join([rpm_dir, "SOURCES", app_archive]),
        target_rpm_path: Path.join([rpm_dir, rpm_file_name(name, version, build_arch)]),
        app_tar_path:    Path.join([build_dir, "rel", Atom.to_string(name), "releases", version, "#{name}.tar.gz"]),
        summary:         @_DEFAULT_SUMMARY,
        description:     @_DEFAULT_DESCRIPTION,
        extra_sources:   @_EXTRA_SOURCES,
      ], do: {item, get_config_item(config, item, default)} )
      |> Enum.into(%{}))
  end

  defp do_spec(config) do
    debug "Generating spec file..."

    dest        = Path.join([config.rpm_dir, "SPECS", "#{config.name}.spec"])
    spec        = get_rpm_template_path(config.priv_path, @_SPEC)

    build_tmp_build(config)

    contents = File.read!(spec)
    |> String.replace(@_NAME, Atom.to_string(config.name))
    |> String.replace(@_VERSION, config.version |> normalize_version)
    |> String.replace(@_RELEASE, config.version)
    |> String.replace(@_TOPDIR, config.rpm_dir)
    |> String.replace(@_BUILD_ARCH, config.build_arch)
    |> String.replace(@_SUMMARY, config.summary)
    |> String.replace(@_DESCRIPTION, config.description)

    File.write!(dest, contents)
    config
  end

  defp do_init_script(config) do
    debug "Generating init.d script..."

    dest = Path.join([config.rpm_dir, "SOURCES", "#{config.name}"])
    File.mkdir_p!(Path.dirname(dest))

    contents = get_rpm_template_path(config.priv_path, @_INIT_FILE)
    |> File.read!
    |> String.replace(@_NAME, Atom.to_string(config.name))

    File.write!(dest, contents)
    config
  end

  defp normalize_version(version) when is_binary(version) do
    version |> String.split([".", "-"]) |> normalize_version |> Enum.join(".")
  end
  defp normalize_version(v = [_maj, _min, _patch]) do
    v
  end
  defp normalize_version(v = [maj, _min, _patch, _pre]) when is_binary(maj) do
    normalize_version(v |> Enum.map(fn(segment) -> Regex.replace(~r/[^0-9]+/, segment, "") |> String.to_integer end))
  end
  defp normalize_version([maj, 0, 0, pre]) when maj > 0 do
    [maj - 1, 99, 99, 99, pre]
  end
  defp normalize_version([maj, min, 0, pre]) when min > 0 do
    [maj, min - 1, 99, 99, pre]
  end
  defp normalize_version([maj, min, patch, pre]) when patch > 0 do
    [maj, min, patch - 1, 99, pre]
  end

  defp copy_extra_sources(config) do
    debug "Copying additional sources..."

    if File.exists? config.extra_sources do
      dest = Path.join([config.rpm_dir, "SOURCES"])
      File.cp_r! config.extra_sources, dest
    end
    config
  end

  defp create_rpm(config) do
    debug "Building rpm..."
    IO.inspect config.sources_path
    File.mkdir_p!(Path.dirname(config.target_rpm_path))
    File.mkdir_p!(Path.dirname(config.sources_path))
    if File.exists? config.app_tar_path do
      File.cp!(config.app_tar_path, config.sources_path)
      run_rpmbulid config, File.exists?(config.rpmbuild)
    else
      error "Could not find the release file #{config.app_tar_path}"
    end
    config
  end

  defp run_rpmbulid(config, rpmbuild?) when rpmbuild? do
    spec_path = Path.join([config.rpm_dir, "SPECS", "#{config.name}.spec"])
    System.cmd(config.rpmbuild, [ config.rpmbuild_opts, spec_path ])

    [build_rpm_path] = Path.join([config.rpm_dir, "RPMS", config.build_arch,
      rpm_file_name(config.name, config.version, config.build_arch, true)]) |> Path.wildcard
    File.copy! build_rpm_path, config.target_rpm_path
    info "RPM #{config.target_rpm_path} created!"
  end

  defp run_rpmbulid(config, _) do
    warn """
    Cannot find rpmbuild tool #{config.rpmbuild}. Skipping rpm build!
    The generated build files can be found in #{config.rpm_dir}
    """
  end

  defp build_tmp_build(config) do
    @_RPM_SPEC_DIRS
    |> Enum.each(&(File.mkdir_p! Path.join([config.rpm_dir | &1])))
    File.mkdir_p! Path.join([config.rpm_dir, "RPMS", config.build_arch])
  end

  defp get_rpm_template_path(priv_path, filename) do
    custom_location = Path.join([File.cwd!, @_RPM_TEMPLATE_DIR, filename])
    if File.exists?(custom_location) do
      custom_location
    else
      Path.join([priv_path, "rel", "files", filename])
    end
  end

  def rpm_file_name(name, version, arch, match \\ false),
    do: "#{name}-#{version |> normalize_version}-0.#{if match, do: "*", else: ""}#{arch}.rpm"

  def get_config_item(config, item, default) do
    app    = config.name
    config |> Map.get(item, Application.get_env(app, item, default))
  end

end
