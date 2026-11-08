import { readdir, readFile, stat, utimes, writeFile } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { promisify } from "node:util";
import { brotliCompress, constants, gzip } from "node:zlib";

const directory = resolve(process.argv[2] ?? "export/web");
const gzipAsync = promisify(gzip);
const brotliAsync = promisify(brotliCompress);
const extensions = new Set([".html", ".js", ".pck", ".wasm"]);

try {
    const files = await readdir(directory, { withFileTypes: true });
    const webFiles = files.filter(file => file.isFile() && extensions.has(extname(file.name)));
    for (const required of [".html", ".js", ".pck", ".wasm"]) {
        if (!webFiles.some(file => extname(file.name) === required)) {
            throw new Error(`Missing ${required} in ${directory}. Run the Godot Web export first.`);
        }
    }

    for (const { name } of webFiles) {
        const path = join(directory, name);
        const source = await readFile(path);
        const metadata = await stat(path);
        const [brotli, gzipped] = await Promise.all([
            brotliAsync(source, { params: { [constants.BROTLI_PARAM_QUALITY]: 9 } }),
            gzipAsync(source, { level: 9 }),
        ]);
        await writeFile(path + ".br", brotli);
        await writeFile(path + ".gz", gzipped);
        await utimes(path + ".br", metadata.atime, metadata.mtime);
        await utimes(path + ".gz", metadata.atime, metadata.mtime);
        console.log(`${name}: ${source.length} B raw, ${brotli.length} B Brotli, ${gzipped.length} B gzip`);
    }
} catch (error) {
    console.error(error.message);
    process.exitCode = 1;
}
