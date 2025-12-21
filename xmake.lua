add_requires("mlir", {
    system = false,
    configs = {
        mode = get_config("mode"),
        debug = is_mode("debug"),
        shared = is_mode("debug") and not is_plat("windows"),
    },
})

local sparse_checkout_list = {
    "cmake",
    "llvm",
    -- "clang",
    "mlir",
    -- "clang-tools-extra",
    "third-party",
}

package("mlir")
    -- add_urls("https://mirrors.tuna.tsinghua.edu.cn/git/llvm-project.git")
    add_urls("https://github.com/llvm/llvm-project.git", {alias = "git", includes = sparse_checkout_list})
    add_versions("git:21.1.7", "llvmorg-21.1.7")
    add_versions("git:20.1.5", "llvmorg-20.1.5")

    add_configs("mode", {description = "Build type", default = "releasedbg", type = "string", values = {"debug", "release", "releasedbg"}})

    if is_plat("windows", "mingw") then
        add_syslinks("version", "ntdll")
    end

    add_deps("cmake", "ninja", "python 3.x", {kind = "binary"})

    if is_host("windows") then
        set_policy("platform.longpaths", true)
    end

    on_load(function (package)
    end)

    on_install(function (package)
        configs = {
            "-DLLVM_ENABLE_ZLIB=OFF",
            "-DLLVM_ENABLE_ZSTD=OFF",
            "-DLLVM_ENABLE_LIBXML2=OFF",
            "-DLLVM_ENABLE_BINDINGS=OFF",
            "-DLLVM_ENABLE_IDE=ON",
            "-DLLVM_ENABLE_ZSTD=OFF",
            "-DLLVM_ENABLE_Z3_SOLVER=OFF",
            "-DLLVM_ENABLE_LIBEDIT=OFF",
            "-DLLVM_ENABLE_LIBPFM=OFF",
            "-DLLVM_ENABLE_LIBXML2=OFF",
            "-DLLVM_ENABLE_OCAMLDOC=OFF",
            "-DLLVM_ENABLE_PLUGINS=OFF",
            "-DLLVM_INCLUDE_UTILS=OFF",
            "-DLLVM_INCLUDE_TESTS=OFF",
            "-DLLVM_INCLUDE_EXAMPLES=OFF",
            "-DLLVM_INCLUDE_BENCHMARKS=OFF",
            "-DLLVM_INCLUDE_DOCS=OFF",
            "-DLLVM_BUILD_UTILS=OFF",
            
            -- "-DLLVM_INCLUDE_TOOLS=OFF",
            "-DCLANG_BUILD_TOOLS=OFF",
            "-DCLANG_INCLUDE_DOCS=OFF",
            "-DCLANG_INCLUDE_TESTS=OFF",
            "-DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF",
            "-DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF",
            "-DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF",
            "-DCLANG_TOOL_LIBCLANG_BUILD=OFF",
            "-DCLANG_ENABLE_CLANGD=OFF",
            "-DLLVM_BUILD_LLVM_C_DYLIB=OFF",
            
            "-DLLVM_ENABLE_RTTI=OFF",

            "-DLLVM_PARALLEL_LINK_JOBS=1",

            -- Build job and link job together will oom
            "-DCMAKE_JOB_POOL_LINK=console",

            "-DLLVM_ENABLE_PROJECTS=mlir",
            

            -- Build all targets, this will affect the builtin type generation.
            -- Users might use a cross-compiler, and to ensure clang works in 
            -- that scenario, we have to build all targets.
            "-DLLVM_TARGETS_TO_BUILD=all",
        }

        -- if package:is_plat("macosx") then
        --     table.insert(configs, "-DLLVM_ENABLE_PROJECTS=mlir")
        --     table.insert(configs, "-DLLVM_ENABLE_LLD=OFF")
        -- else
        --     table.insert(configs, "-DLLVM_ENABLE_PROJECTS=lld;mlir")
        -- end

        -- if package:is_plat("macosx", "linux") then
        --     table.insert(configs, "-DCMAKE_C_COMPILER=clang")
        --     table.insert(configs, "-DCMAKE_CXX_COMPILER=clang++")
        -- end

        -- if package:is_plat("windows") then
        --     table.insert(configs, "-DLLVM_ENABLE_LLD=OFF")
        -- end 

        local build_type = {
            ["debug"] = "Debug",
            ["release"] = "Release",
            ["releasedbg"] = "RelWithDebInfo",
        }

        table.insert(configs, "-DCMAKE_BUILD_TYPE=" .. (build_type[package:config("mode")]))
        table.insert(configs, "-DBUILD_SHARED_LIBS=" .. (package:config("shared") and "ON" or "OFF"))
        table.insert(configs, "-DLLVM_ENABLE_LTO=" .. (package:config("lto") and "ON" or "OFF"))
        table.insert(configs, "-DMLIR_LINK_MLIR_DYLIB=" .. (not package:config("debug") and "ON" or "OFF"))
        table.insert(configs, "-DLLVM_LINK_LLVM_DYLIB=" .. (not package:config("debug") and "ON" or "OFF"))
        table.insert(configs, "-DLLVM_BUILD_TOOLS=" .. (not package:config("debug") and "ON" or "OFF"))
        

        if package:config("mode") == "debug" then
            table.insert(configs, "-DLLVM_USE_SANITIZER=Address")
        end

        if package:is_plat("windows") then
            -- table.insert(configs, "-DCMAKE_C_COMPILER=clang-cl")
            -- table.insert(configs, "-DCMAKE_CXX_COMPILER=clang-cl")
            -- table.insert(configs, "-DLLVM_OPTIMIZED_TABLEGEN=ON")
            -- table.insert(configs, "-DLLVM_ENABLE_PROJECTS=lld;mlir")
            -- table.insert(configs, "-DLLVM_USE_LINKER=lld")
        elseif package:is_plat("linux") then
            table.insert(configs, "-DLLVM_USE_LINKER=lld")
            -- table.insert(configs, "-DLLVM_ENABLE_PROJECTS=mlir")
            -- table.insert(configs, "-DLLVM_USE_SPLIT_DWARF=ON")
        elseif package:is_plat("macosx") then
            table.insert(configs, "-DCMAKE_OSX_ARCHITECTURES=arm64")
            table.insert(configs, "-DCMAKE_LIBTOOL=/opt/homebrew/opt/llvm@20/bin/llvm-libtool-darwin")
            table.insert(configs, "-DLLVM_USE_LINKER=lld")
            table.insert(configs, "-DLLVM_ENABLE_LIBCXX=ON")
            -- table.insert(configs, "-DLLVM_ENABLE_PROJECTS=mlir")
        end

        os.cd("llvm")
        import("package.tools.cmake")

        if package:is_plat("windows") then
            --* seems that there is something about project race condition about msvc/clang-cl...
            --* LNK: https://github.com/DvdBr3o/prebuilt-mlir/actions/runs/20406932570/job/58637984740
            print("Fixing Windows MSBuild race condition: Pre-generating MLIR headers...")
            cmake.build(package, configs, {target = "mlir-tablegen-targets"})
            cmake.build(package, configs, {target = "mlir-headers"})
        end
        
        cmake.install(package, configs)

        -- if package:is_plat("windows") then
        --     for _, file in ipairs(os.files(package:installdir("bin/*"))) do
        --         if not file:endswith(".dll") then
        --             os.rm(file)
        --         end
        --     end
        -- elseif package:is_plat("linux") then
        --     os.rm(package:installdir("bin/*"))
        -- end

        local abi
        local format
        if package:is_plat("windows") then
            abi = "msvc"
            format = ".7z"
        elseif package:is_plat("linux") then
            abi = "gnu"
            format = ".tar.xz"
        elseif package:is_plat("macosx") then
            abi = "apple"
            format = ".tar.xz"
        end
        -- arch-plat-abi-mode
        local archive_name = table.concat({
            package:arch(),
            package:plat(),
            abi,
            package:config("mode"),
        }, "-")

        if package:config("lto") then
            archive_name = archive_name .. "-lto"
        end

        local archive_file = path.join(os.scriptdir(), "build/package", archive_name .. format)

        local opt = {}
        opt.recurse = true
        opt.compress = "best"
        opt.curdir = package:installdir()

        local archive_dirs
        if package:is_plat("windows") then
            archive_dirs = "*"
        elseif package:is_plat("linux", "macosx") then
            -- workaround for tar
            archive_dirs = {}
            for _, dir in ipairs(os.dirs(path.join(opt.curdir, "*"))) do
                table.insert(archive_dirs, path.filename(dir))
            end
        end
        import("utils.archive").archive(archive_file, archive_dirs, opt)

        local checksum = hash.sha256(archive_file)
        print(checksum)
    end)