use ::core::{
    ffi::{c_char, c_void},
    ptr,
};

use ngx::{
    core::{Buffer, Status},
    ffi::{
        NGX_CONF_NOARGS, NGX_CONF_TAKE1, NGX_HTTP_LOC_CONF,
        NGX_HTTP_LOC_CONF_OFFSET, NGX_HTTP_MODULE, NGX_HTTP_SRV_CONF,
        ngx_array_push, ngx_atomic_t, ngx_chain_t, ngx_command_t, ngx_conf_t,
        ngx_http_handler_pt, ngx_http_module_t,
        ngx_http_phases_NGX_HTTP_CONTENT_PHASE, ngx_int_t, ngx_module_t,
        ngx_str_t, ngx_uint_t,
    },
    http::{
        self, HTTPStatus, HttpModule, HttpModuleLocationConf,
        HttpModuleMainConf, MergeConfigError, Method, NgxHttpCoreModule,
    },
    http_request_handler, ngx_log_debug_http, ngx_string,
};

struct Module;

unsafe extern "C" {
    // const instead of must just because we don't need to modify them
    static ngx_stat_accepted: *const ngx_atomic_t;
    static ngx_stat_handled: *const ngx_atomic_t;
    static ngx_stat_active: *const ngx_atomic_t;
    static ngx_stat_requests: *const ngx_atomic_t;
    static ngx_stat_reading: *const ngx_atomic_t;
    static ngx_stat_writing: *const ngx_atomic_t;
    static ngx_stat_waiting: *const ngx_atomic_t;
}

impl http::HttpModule for Module {
    fn module() -> &'static ngx_module_t {
        unsafe { &*ptr::addr_of!(ngx_http_curl_module) }
    }

    unsafe extern "C" fn postconfiguration(cf: *mut ngx_conf_t) -> ngx_int_t {
        // SAFETY: this function is called with non-NULL cf always
        let cf = unsafe { &mut *cf };

        let cmcf =
            NgxHttpCoreModule::main_conf_mut(cf).expect("http core main conf");
        let handler = unsafe {
            ngx_array_push(
                &mut cmcf.phases
                    // We want to _replace_ the content with metrics
                    [ngx_http_phases_NGX_HTTP_CONTENT_PHASE as usize]
                    .handlers,
            )
            .cast::<ngx_http_handler_pt>()
        };
        if handler.is_null() {
            return Status::NGX_ERROR.into();
        }
        // Set phase handler
        // SAFETY: is not null as check above
        unsafe {
            *handler = Some(curl_access_handler);
        }

        // Check if stats are initialized
        // SAFETY: Just checking if they are null
        if unsafe {
            ngx_stat_accepted.is_null()
                || ngx_stat_handled.is_null()
                || ngx_stat_active.is_null()
                || ngx_stat_requests.is_null()
                || ngx_stat_reading.is_null()
                || ngx_stat_writing.is_null()
                || ngx_stat_waiting.is_null()
        } {
            return Status::NGX_ERROR.into();
        }

        Status::NGX_OK.into()
    }
}

#[derive(Debug, Default)]
struct ModuleConfig {
    enable: bool,
}

unsafe impl HttpModuleLocationConf for Module {
    type LocationConf = ModuleConfig;
}

static mut NGX_HTTP_PROMETHEUS_EXPORTER_COMMANDS: [ngx_command_t; 2] = [
    ngx_command_t {
        name: ngx_string!("prometheus_exporter"),
        type_: (NGX_HTTP_SRV_CONF
            | NGX_HTTP_LOC_CONF
            | NGX_CONF_NOARGS
            | NGX_CONF_TAKE1) as ngx_uint_t,
        // type_: (NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF | NGX_CONF_FLAG) as ngx_uint_t,
        set: Some(ngx_http_curl_commands_set_enable),
        // set: Some(ngx_conf_set_flag_slot),
        conf: NGX_HTTP_LOC_CONF_OFFSET,
        offset: 0,
        // offset: mem::offset_of!(ModuleConfig, enable),
        post: ptr::null_mut(),
    },
    ngx_command_t::empty(),
];

static NGX_HTTP_CURL_MODULE_CTX: ngx_http_module_t = ngx_http_module_t {
    preconfiguration: Some(Module::preconfiguration),
    postconfiguration: Some(Module::postconfiguration),
    create_main_conf: None,
    init_main_conf: None,
    create_srv_conf: None,
    merge_srv_conf: None,
    create_loc_conf: Some(Module::create_loc_conf),
    merge_loc_conf: Some(Module::merge_loc_conf),
};

// Generate the `ngx_modules` table with exported modules.
// This feature is required to build a 'cdylib' dynamic module outside of the NGINX buildsystem.
#[cfg(feature = "export-modules")]
ngx::ngx_modules!(ngx_http_curl_module);

#[used]
#[allow(non_upper_case_globals)]
#[cfg_attr(not(feature = "export-modules"), unsafe(no_mangle))]
pub static mut ngx_http_curl_module: ngx_module_t = ngx_module_t {
    ctx: std::ptr::addr_of!(NGX_HTTP_CURL_MODULE_CTX) as _,
    commands: unsafe {
        (&raw const NGX_HTTP_PROMETHEUS_EXPORTER_COMMANDS[0]).cast_mut()
    },
    type_: NGX_HTTP_MODULE as _,
    ..ngx_module_t::default()
};

impl http::Merge for ModuleConfig {
    fn merge(&mut self, prev: &Self) -> Result<(), MergeConfigError> {
        if prev.enable {
            self.enable = true;
        }
        Ok(())
    }
}

http_request_handler!(curl_access_handler, |request: &mut http::Request| {
    let co = Module::location_conf(request).expect("module config is none");
    if !co.enable {
        return Status::NGX_DECLINED;
    }

    ngx_log_debug_http!(
        request,
        "prometheus_exporter module enabled: {}",
        co.enable
    );

    // Only respond to GET/HEAD requests
    if !matches!(request.method(), Method::GET | Method::HEAD) {
        return http::HTTPStatus::NOT_ALLOWED.into();
    }

    let rc = request.discard_request_body();
    if rc != Status::NGX_OK {
        return rc;
    }

    let content = format!(
        r"# HELP nginx_connections_accepted Accepted client connections
# TYPE nginx_connections_accepted counter
nginx_connections_accepted {stat_accepted}
# HELP nginx_connections_active Active client connections
# TYPE nginx_connections_active gauge
nginx_connections_active {stat_active}
# HELP nginx_connections_handled Handled client connections
# TYPE nginx_connections_handled counter
nginx_connections_handled {stat_handled}
# HELP nginx_connections_reading Connections where NGINX is reading the request header
# TYPE nginx_connections_reading gauge
nginx_connections_reading {stat_reading}
# HELP nginx_connections_waiting Idle client connections
# TYPE nginx_connections_waiting gauge
nginx_connections_waiting {stat_waiting}
# HELP nginx_connections_writing Connections where NGINX is writing the response back to the client
# TYPE nginx_connections_writing gauge
nginx_connections_writing {stat_writing}
# HELP nginx_http_requests_total Total http requests
# TYPE nginx_http_requests_total counter
nginx_http_requests_total {stat_requests}
",
        // SAFETY: All checked in `postconfiguration` to _not_ be null ptrs
        stat_accepted = unsafe { *ngx_stat_accepted },
        stat_active = unsafe { *ngx_stat_active },
        stat_handled = unsafe { *ngx_stat_handled },
        stat_reading = unsafe { *ngx_stat_reading },
        stat_waiting = unsafe { *ngx_stat_waiting },
        stat_writing = unsafe { *ngx_stat_writing },
        stat_requests = unsafe { *ngx_stat_requests },
    );

    let Some(mut buffer) = request.pool().create_buffer_from_str(&content)
    else {
        return http::HTTPStatus::INTERNAL_SERVER_ERROR.into();
    };

    request.set_content_length_n(buffer.len());
    request.set_status(HTTPStatus::OK);

    buffer.set_last_buf(request.is_main());
    buffer.set_last_in_chain(true);

    let rc = request.send_header();
    if rc == Status::NGX_ERROR || rc > Status::NGX_OK || request.header_only()
    {
        return rc;
    }

    let mut out = ngx_chain_t {
        buf: buffer.as_ngx_buf_mut(),
        next: std::ptr::null_mut(),
    };
    request.output_filter(&mut out)
});

extern "C" fn ngx_http_curl_commands_set_enable(
    cf: *mut ngx_conf_t,
    _cmd: *mut ngx_command_t,
    conf: *mut c_void,
) -> *mut c_char {
    let conf = unsafe { &mut *conf.cast::<ModuleConfig>() };
    let cf = unsafe { &mut *cf };

    // set default value optionally
    conf.enable = true;

    let args = unsafe { &mut (*(cf.args)) };
    if args.nelts == 2 {
        let elts = args.elts.cast::<ngx_str_t>();
        // Get second argument, first is module name
        let val = unsafe { (*elts.add(1)).to_str() };

        if val.len() == 2 && val.eq_ignore_ascii_case("on") {
            conf.enable = true;
        } else if val.len() == 3 && val.eq_ignore_ascii_case("off") {
            conf.enable = false;
        } else {
            // TODO: return ERROR
        }
    }

    // NGX_CONF_OK
    ptr::null_mut()
}
