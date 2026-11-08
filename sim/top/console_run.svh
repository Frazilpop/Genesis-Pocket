// A game, whole: the real console behind core_top.sv, the ROM through the bridge into
// the SDRAM, the frames as they reach the Pocket's video pins.
//   +rom=FILE +frames=N +every=K +out=DIR  [+press=F] Start held for some frames from frame F
//   [+rows=N] the region's rows as the game starts: Region's value, and 4 for PAL 60 Hz
//   [+composite=N] Composite Blend's value, written after boot as the menu would
//   [+anz=V,V,...] the Analogizer on, each video code in turn (pocket_analogizer.sv): its
//   word written at frame +anz_at=F (20) and every 3 frames after, the cartridge pins at
//   every clk_sys edge of the next two frames in anz_vNN.raw (anz.svh), the Pocket's
//   frames every frame from F on; sim/top/anz.py holds the two against each other
int frame_no = 0, px = 0, py = 0, frames_wanted = 300, every = 60, press_at = -1, composite = 0;
string out_dir = ".";
reg [23:0] fb [0:320 * 240 - 1];
int width = 0, height = 0;
int frames_fd = 0;
longint frame_hash = 0;

always @(posedge video_rgb_clock) begin
    if (video_de) begin
        if (px < 320 && py < 240) fb[py * 320 + px] = video_rgb;
        frame_hash = (frame_hash ^ longint'(video_rgb)) * 64'h100000001B3;
        px++;
    end
    if (video_hs) begin
        if (px > 0) begin
            width = px;
            py++;
        end
        px = 0;
    end
    if (video_vs) begin
        height = py;
        if (frames_fd != 0) $fdisplay(frames_fd, "%0d %0dx%0d %h %0d", frame_no, width, height, frame_hash, $time);
        if (frame_no % every == 0 && frames_fd != 0 && height > 0) begin
            automatic int fd = $fopen($sformatf("%s/f_%05d.hex", out_dir, frame_no), "w");
            $fdisplay(fd, "%0d %0d", width, height);
            // (fb is 320 a row whatever the width, so an H32 line is the first 256 of its row)
            for (int i = 0; i < width * height; i++) $fdisplay(fd, "%06x", fb[(i / width) * 320 + i % width]);
            $fclose(fd);
        end
        frame_no++;
        frame_hash = 64'hCBF29CE484222325;
        py = 0;
    end
    if (press_at >= 0) cont1_key = frame_no >= press_at && frame_no < press_at + 10 ? 16'h8000 : 16'h0000;
end

string anz_list = "";
int    anz_at = 20;
task automatic anz_run();
    int v[$];
    int n = 0;
    void'($value$plusargs("anz_at=%d", anz_at));
    for (int i = 0; i <= anz_list.len(); i++)
        if (i == anz_list.len() || anz_list[i] == ",") begin v.push_back(n); n = 0; end
        else n = n * 10 + (anz_list[i] - "0");
    every = 1 << 30;
    wait (frame_no >= anz_at - 1);
    every = 1;
    foreach (v[i]) begin
        automatic int fd;
        wait (frame_no >= anz_at + 3 * i);
        anz_file(anz_word(0, 1, 0, v[i]));
        wait (frame_no >= anz_at + 3 * i + 1);
        anz_samples = 0;
        anz_fd = $fopen($sformatf("%s/anz_v%02d.raw", out_dir, v[i]), "wb");
        wait (frame_no >= anz_at + 3 * i + 3);
        fd = anz_fd; anz_fd = 0; $fclose(fd);
        fd = $fopen($sformatf("%s/anz_v%02d.txt", out_dir, v[i]), "w");
        $fdisplay(fd, "video %0d frames %0d %0d samples %0d ps %0d %0d h40 %0d pal %0d",
                  v[i], anz_at + 3 * i + 1, anz_at + 3 * i + 3, anz_samples, anz_t0, anz_t1, ic.resolution[0], ic.pal_s);
        $fclose(fd);
        $display("Analogizer video %0d: %0d clocks", v[i], anz_samples);
    end
    every = 1 << 30;
endtask

task automatic run();
    string path;
    int fd;
    if (!$value$plusargs("rom=%s", path)) $fatal(1, "+rom=FILE");
    void'($value$plusargs("frames=%d", frames_wanted));
    void'($value$plusargs("every=%d", every));
    void'($value$plusargs("press=%d", press_at));
    void'($value$plusargs("out=%s", out_dir));
    void'($value$plusargs("rows=%d", row_before_load));
    void'($value$plusargs("composite=%d", composite));
    fd = $fopen(path, "rb");
    rom_size = $fread(rom, fd);
    $fclose(fd);
    $display("%s: %0d bytes", path, rom_size);
    frames_fd = $fopen({out_dir, "/frames.txt"}, "w");
    boot();
    $display("Booted");
    if (composite != 0) bwr(`A_COMPOSITE, composite, 20);
    start_game();
    $display("The game is in, frame %0d of the picture", frame_no);
    if ($value$plusargs("anz=%s", anz_list)) anz_run();
    while (frame_no < frames_wanted) begin
        automatic int starts = pll_starts;
        tick(100000);
        $display("%0d of %0d frames", frame_no, frames_wanted);
        if (pll_starts != starts) $display("the clock changes at frame %0d: K %0d", frame_no, pll_k);
    end
    $fclose(frames_fd);
    frames_fd = 0;
endtask
