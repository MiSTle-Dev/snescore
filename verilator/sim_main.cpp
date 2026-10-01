#include <cstdio>
#include <iostream>
#include <SDL.h>
#include <cstdlib>
#include <climits>
#include <cstring>
#include <vector>
#include <cctype>
#include <chrono>
#include <thread>

#include "Vsnestang_top.h"
#include "Vsnestang_top_snestang_top.h"
#include "verilated.h"
#include <verilated_fst_c.h>

#ifdef ENABLE_COMPANION
#include "sd_card_config.h"
#endif

#define SYS_CLK (21.5054)

#define TRACE_ON

using namespace std;

// See: https://projectf.io/posts/verilog-sim-verilator-sdl/
const int H_RES = 256;
const int V_RES = 224;		// E0

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;

Pixel screenbuffer[H_RES*V_RES];

bool trace = false;

void usage() {
	printf("Usage: sim [-r ROM."
#ifdef ENABLE_COMPANION	       
	       "sfc/smc"
#else
	       "hex"
#endif
	       "] [-t] [-c T]\n");
	printf("  -r FILE load FILE as the SNES ROM (maximum 4 MiB)\n");
	printf("  -t     output trace file waveform.fst\n");
	printf("  -s T0  start tracing from time T0 milliseconds\n");
	printf("  -c T   limit simulate length to T milliseconds. T=0 means infinite.\n");
}

VerilatedFstC *m_trace;
Vsnestang_top* top;

// split by spaces
vector<string> tokenize(string s);
void trace_on();
void trace_off();

#ifdef ENABLE_COMPANION
Vsnestang_top* tb;  // sd_card expects a global tb

// optionally parse a sector address into track/side/sector
char *sector_string(int drive, uint32_t lba) {
  static char str[32];
  strcpy(str, "");
  return str;
}
#endif

double simulation_time = 0.0;
// Default 50ms
double max_sim_time = 0.05;
double start_trace_time = 0.0;

int main(int argc, char** argv, char** env) {
	// Accept a conventional option and translate it to the Verilog plusarg
	// consumed by test_loader. Direct +ROM=... remains supported as well.
	vector<string> command_strings;
	vector<char*> command_args;
	command_strings.reserve(argc + 1);
	command_args.reserve(argc + 1);
	for (int i = 0; i < argc; i++) {
		if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) {
#ifdef ENABLE_COMPANION
			sd_set_file(0, argv[++i]);
#else
			command_strings.emplace_back(string("+ROM=") + argv[++i]);
#endif
		} else {
			command_strings.emplace_back(argv[i]);
		}
	}
	for (string& arg : command_strings)
		command_args.push_back(arg.data());
	Verilated::commandArgs(command_args.size(), command_args.data());
	Vsnestang_top* new_top = new Vsnestang_top;
	top = new_top;
#ifdef ENABLE_COMPANION
	tb = new_top;
#endif
	Vsnestang_top_snestang_top *snes = top->snestang_top;
	bool frame_updated = false;
	uint64_t start_ticks = SDL_GetPerformanceCounter();
	int frame_count = 0;

	// parse options
	for (int i = 1; i < argc; i++) {
		char *eptr;
		if (strcmp(argv[i], "-t") == 0) {
			trace = true;
			printf("Tracing ON\n");
		} else if (strcmp(argv[i], "-c") == 0 && i+1 < argc) {
			max_sim_time = strtof(argv[++i], &eptr) / 1000.0;
			if (max_sim_time == 0)
				printf("Simulating forever.\n");
			else
				printf("Simulating %.3f ms\n", max_sim_time*1000.0);
		} else if (strcmp(argv[i], "-r") == 0 && i+1 < argc) {
			i++;
			printf("Loading ROM %s\n", argv[i]);
		} else if (strncmp(argv[i], "+ROM=", 5) == 0) {
			printf("Loading ROM %s\n", argv[i] + 5);
		} else if (strcmp(argv[i], "-s") == 0 && i+1 < argc) {
			start_trace_time = strtof(argv[++i], &eptr) / 1000.0;
			printf("Start tracing from %.3f ms\n", start_trace_time*1000.0);
		} else {
			printf("Unrecognized option: %s\n", argv[i]);
			usage();
			exit(1);
		}
	}

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL init failed.\n");
        return 1;
    }

    SDL_Window*   sdl_window   = NULL;
    SDL_Renderer* sdl_renderer = NULL;
    SDL_Texture*  sdl_texture  = NULL;

    sdl_window = SDL_CreateWindow("snestang", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, H_RES*2, V_RES*2, SDL_WINDOW_SHOWN);
    if (!sdl_window) {
        printf("Window creation failed: %s\n", SDL_GetError());
        return 1;
    }
    sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!sdl_renderer) {
        printf("Renderer creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_STREAMING, H_RES, V_RES);
    if (!sdl_texture) {
        printf("Texture creation failed: %s\n", SDL_GetError());
        return 1;
    }

#ifdef ENABLE_COMPANION
    sd_init();
#endif
    
	if (trace)
		trace_on();

	int audio_ready_r = 0;
	FILE *f = fopen("snes.aud", "w");
	long long samples = 0;

	while (max_sim_time == 0 || simulation_time < max_sim_time) {
		top->sys_clk ^= 1;

#ifdef ENABLE_COMPANION
		// handle sd card emulation on one edge of the 1/6 sys_clk
		// which in turn is the mclk the sd card itself runs on
		static int mcnt = 0;
		if(++mcnt == 12) {
		  sd_handle();
		  mcnt = 0;
		}
#endif
		top->eval();
		
		// tracing happens in picoseconds
		if (trace && simulation_time >= start_trace_time)
			m_trace->dump(1000000000000 * simulation_time);

		// collect audio sample
		if (snes->audio_ready && audio_ready_r == 0) {
			short ar, al;
			ar = snes->audio_r;
			al = snes->audio_l;
			fwrite(&ar, sizeof(ar), 1, f);
			fwrite(&al, sizeof(al), 1, f);
			samples ++;
			if (samples % 1000 == 0)
			  printf("%.3fms %lld samples\n", simulation_time*1000, samples);
			// printf("%hd %hd\n", top->spcplayer_top->audio_l, top->spcplayer_top->audio_r);
		}
		audio_ready_r = snes->audio_ready;

		// Y_OUT[8] is the interlace field; both fields use the same SDL rows.
		const unsigned y = snes->y_out & 0xFF;
		const int field = snes->y_out & 0x100;

		// if the screen is black consider using !field
		if (field && y < V_RES && (snes->x_out >> 1) < H_RES) {
			Pixel* p = &screenbuffer[y*H_RES + (snes->x_out >> 1)];
			p->a = 0xFF;  // transparency
			p->b = snes->B_OUT;
			p->g = snes->G_OUT;
			p->r = snes->R_OUT;
		}

		// check for quit event
		static int poll_cnt = 0;
		if(poll_cnt++ == 10000) {
			SDL_Event e;
			if ((SDL_PollEvent(&e)) && (e.type == SDL_QUIT))
					break;
			poll_cnt = 0;
		}

		// update texture once per frame (in blanking)
		if (y == V_RES) {
			if (!frame_updated) {
				frame_updated = true;
				if (SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES*sizeof(Pixel)) < 0) {
					fprintf(stderr, "Texture update failed: %s\n", SDL_GetError());
					break;
				}
				SDL_RenderClear(sdl_renderer);
				if (SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL) < 0) {
					fprintf(stderr, "Frame render failed: %s\n", SDL_GetError());
					break;
				}
				SDL_RenderPresent(sdl_renderer);
				frame_count++;

				if (frame_count % 10 == 0)
				  printf("%.3fms Frame #%d\n", simulation_time*1000, frame_count);
			}
		} else
			frame_updated = false;

		simulation_time += 1.0/1000000/SYS_CLK/12;
	}


	printf("Simulation done, time=%.3f ms\n", simulation_time*1000.0);

	fclose(f);
	printf("Audio output to snes.aud done.\n");

	if (m_trace)
		m_trace->close();
	delete top;

    // calculate frame rate
    uint64_t end_ticks = SDL_GetPerformanceCounter();
    double duration = ((double)(end_ticks-start_ticks))/SDL_GetPerformanceFrequency();
    double fps = (double)frame_count/duration;
    printf("Frames per second: %.1f. Total frames=%d\n", fps, frame_count);

    // std::this_thread::sleep_for(std::chrono::seconds(5));

    SDL_DestroyTexture(sdl_texture);
    SDL_DestroyRenderer(sdl_renderer);
    SDL_DestroyWindow(sdl_window);
    SDL_Quit();

	return 0;
}

bool is_space(char c) {
	return c == ' ' || c == '\t';
}

vector<string> tokenize(string s) {
	string w;
	vector<string> r;

	for (int i = 0; i < s.size(); i++) {
		char c = s[i];
		if (is_space(c) && w.size() > 0) {
			r.push_back(w);
			w = "";
		}
		if (!is_space(c))
			w += c;
	}
	if (w.size() > 0)
		r.push_back(w);
	return r;
}

void trace_on() {
	if (!m_trace) {
		m_trace = new VerilatedFstC;
		top->trace(m_trace, 5);
		Verilated::traceEverOn(true);
		m_trace->open("waveform.fst");
	}
}

void trace_off() {
	if (m_trace) {
		top->trace(m_trace, 0);
	}
}
