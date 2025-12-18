-- usage: xmake l release.lua
-- Add proxy: xmake g --proxy=ip:port

import("core.base.json")
import("core.base.global")
import("devel.git")
import("utils.archive")

function _get_current_commit_hash()
	return os.iorunv("git rev-parse --short HEAD"):trim()
end

function _get_current_tag()
	return os.iorunv("git describe --tags --abbrev=0"):trim()
end

-- @param llvm_archive string
-- @param unused_libs array
-- @return archive_file string
function _reduce_package_size(llvm_archive, unused_libs)
	local workdir = "build/.pack"
	os.tryrm(workdir)

	local archive_name = path.filename(llvm_archive)
	print("extract ", archive_name)
	archive.extract(llvm_archive, workdir)

	print("handle ", archive_name)
	-- we use dynamic lib for debug mode, and its deps are
	-- different with release, so skip them now.
	if llvm_archive:find("releasedbg") then
		for _, lib in ipairs(unused_libs) do
			os.rm(path.join(workdir, format("lib/%s.*", lib)))
		end
	end

	local opt = {}
	opt.recurse = true
	opt.compress = "best"
	opt.curdir = workdir

	local archive_dirs
	if is_host("windows") then
		archive_dirs = "*"
	elseif is_host("linux", "macosx") then
		-- workaround for tar
		archive_dirs = {}
		for _, dir in ipairs(os.dirs(path.join(opt.curdir, "*"))) do
			table.insert(archive_dirs, path.filename(dir))
		end
	end

	print("archive ", archive_name)
	os.mkdir("build/pack")
	local archive_file = path.absolute(path.join("build/pack", archive_name))
	import("utils.archive").archive(archive_file, archive_dirs, opt)
	return archive_file
end

function main()
	local envs = {}
	if global.get("proxy") then
		envs.HTTPS_PROXY = global.get("proxy")
	end

	local tag = _get_current_tag()
	local current_commit = _get_current_commit_hash()

	print("current tag: ", tag)
	print("current commit: ", current_commit)

	local dir = path.join(os.scriptdir(), "artifacts", current_commit)
	os.mkdir(dir)

	local workflow = os.host()
	if is_host("macosx") then
		workflow = "macos"
	end
	-- Get latest workflow id
	local result = json.decode(os.iorunv(format("gh run list --json databaseId --limit 1 --workflow=%s.yml", workflow)))
	for _, json in pairs(result) do
		-- float -> int
		local run_id = format("%d", json["databaseId"])
		-- download all artifacts
		os.execv("gh", { "run", "download", run_id, "--dir", dir }, { envs = envs })
	end

	local origin_files = {}
	table.join2(origin_files, os.files(path.join(dir, "**.7z")))
	table.join2(origin_files, os.files(path.join(dir, "**.tar.xz")))

	print(origin_files)

	local files = {}
	for _, llvm_archive in ipairs(origin_files) do
		table.insert(files, _reduce_package_size(path.absolute(llvm_archive), unused_libs))
	end

	local binaries = {}
	-- greater than 2 Gib?
	for _, i in ipairs(files) do
		local file = io.open(i, "r")
		local size, error = file:size()
		-- github release limit 2 Gib
		if size > 2 * 1024 * 1024 * 1024 then
			print("%s > 2 Gib, skip", path.filename(i))
			print(file)
		else
			table.insert(binaries, i)
		end
	end

	-- gh release create "$TAG" --title "Prebuilt LLVM mlir $TAG" --notes "Auto publish."
	try({
		os.execv(
			"gh",
			{ "release", "create", tag, "--title", "Prebuilt LLVM mlir " .. tag, "--notes", '"Auto publish."' }
		),
		catch({ function(err) end }),
	})

	print(binaries)
	-- clobber: overwrite
	for _, binary in ipairs(binaries) do
		os.execv("gh", { "release", "upload", tag, binary, "--clobber" }, { envs = envs })
	end
end
