"""
HTTP Server for Scout Receiver

Async HTTP server using aiohttp to accept SCOUT Agent data,
provide heartbeat endpoints, and serve a monitoring dashboard.
"""

import asyncio
import json
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional, Set

from aiohttp import web, WSMsgType
from aiohttp.web_request import Request
from aiohttp.web_response import Response

try:
    import aiohttp_cors
    HAS_CORS = True
except ImportError:
    HAS_CORS = False

from .heartbeat import HeartbeatHandler
from .statistics import StatisticsCollector
from .storage import ScoutDataStorage
from .utils.config import ScoutReceiverConfig, load_config
from .utils.logging import get_logger, get_packet_logger, setup_logging
from .validation import DataValidator

logger = get_logger(__name__)
packet_logger = get_packet_logger()


class ScoutReceiverServer:
    """HTTP Server for receiving SCOUT Agent data.

    Provides endpoints for:
    - Data reception (/scout/data, /scout/events, /scout/system)
    - Health checks (/scout/health, /scout/status)
    - Control endpoints (/control/*)
    - Web dashboard (/, /api/*)
    """

    def __init__(self, config: Optional[ScoutReceiverConfig] = None):
        """Initialize Scout Receiver Server.

        Args:
            config: Configuration manager instance
        """
        self.config = config or load_config()

        # Initialize components
        self.validator = DataValidator(self.config.get_section('validation'))
        self.storage = ScoutDataStorage(self.config.get_section('storage'))
        self.heartbeat = HeartbeatHandler(self.config.get_section('heartbeat'))
        self.statistics = StatisticsCollector()

        # Server state
        self.app = web.Application()
        self.is_running = False
        self.start_time: Optional[float] = None

        # WebSocket connections for real-time updates
        self.websocket_connections: Set[web.WebSocketResponse] = set()

        # Recent received data (for dashboard)
        self.received_data: list = []
        self.max_received_data = 100

        # Setup routes and middleware
        self._setup_routes()
        self._setup_cors()
        self._setup_middleware()

    def _setup_routes(self) -> None:
        """Configure HTTP routes."""
        router = self.app.router

        # Data reception endpoints
        router.add_post('/scout/data', self._handle_scout_data)
        router.add_post('/scout/events', self._handle_scout_events)
        router.add_post('/scout/system', self._handle_scout_system)

        # Health and status endpoints
        router.add_get('/scout/health', self._handle_health)
        router.add_get('/scout/status', self._handle_status)
        router.add_get('/scout/metrics', self._handle_metrics)

        # Control endpoints
        router.add_post('/control/heartbeat', self._handle_control_heartbeat)
        router.add_post('/control/simulate', self._handle_control_simulate)
        router.add_get('/control/stats', self._handle_control_stats)
        router.add_post('/control/reset', self._handle_control_reset)

        # Web interface endpoints
        router.add_get('/', self._handle_dashboard)
        router.add_get('/api/data', self._handle_api_data)
        router.add_get('/api/statistics', self._handle_api_statistics)
        router.add_get('/api/storage', self._handle_api_storage)
        router.add_get('/ws', self._handle_websocket)

    def _setup_cors(self) -> None:
        """Configure CORS for web interface access."""
        if not HAS_CORS:
            logger.warning("aiohttp-cors not installed, CORS disabled")
            return

        if not self.config.get('server.cors_enabled', True):
            return

        cors = aiohttp_cors.setup(self.app, defaults={
            "*": aiohttp_cors.ResourceOptions(
                allow_credentials=True,
                expose_headers="*",
                allow_headers="*",
                allow_methods="*"
            )
        })

        for route in list(self.app.router.routes()):
            try:
                cors.add(route)
            except ValueError:
                pass  # Some routes may not support CORS

    def _setup_middleware(self) -> None:
        """Configure request middleware."""

        @web.middleware
        async def logging_middleware(request: Request, handler):
            """Log all incoming requests."""
            start_time = time.time()

            try:
                response = await handler(request)
                processing_time = time.time() - start_time

                # Log at debug level for health checks
                log_func = (logger.debug if request.path == '/scout/health'
                           else logger.info)
                log_func(
                    f"{request.method} {request.path} -> {response.status} "
                    f"({processing_time*1000:.1f}ms)"
                )

                return response

            except Exception as e:
                processing_time = time.time() - start_time
                logger.error(
                    f"{request.method} {request.path} -> ERROR: {e} "
                    f"({processing_time*1000:.1f}ms)"
                )
                raise

        self.app.middlewares.append(logging_middleware)

    # ==================== Data Reception Handlers ====================

    async def _handle_scout_data(self, request: Request) -> Response:
        """Handle SCOUT Agent data POST requests."""
        start_time = time.time()
        client_ip = request.remote or 'unknown'

        try:
            # Extract headers
            content_type = request.headers.get('Content-Type', '')
            data_size = int(request.headers.get('Content-Length', 0))
            agent_version = request.headers.get('X-Scout-Agent-Version', 'unknown')
            host_id = request.headers.get('X-Scout-Host-ID', 'unknown')
            data_type = request.headers.get('X-Scout-Data-Type', 'unknown')
            checksum = request.headers.get('X-Scout-Checksum', '')

            # Read and parse request body
            if 'application/json' in content_type:
                data = await request.json()
            elif 'application/x-ndjson' in content_type:
                text = await request.text()
                data = [json.loads(line) for line in text.strip().split('\n') if line]
            else:
                data = await request.read()
                data = data.decode('utf-8', errors='replace')

            # Log packet reception
            packet_logger.log_packet_received(
                source_ip=client_ip,
                packet_size=data_size,
                protocol='HTTP',
                timestamp=start_time
            )

            # Validate data envelope
            envelope = {
                'agent_version': agent_version,
                'host_id': host_id,
                'timestamp': start_time,
                'data_type': data_type,
                'checksum': checksum,
                'data': data,
            }
            validation_result = self.validator.validate_data_envelope(envelope)

            # Verify checksum if provided
            if checksum and self.config.get('validation.verify_checksums', True):
                if isinstance(data, (dict, list)):
                    data_str = json.dumps(data, sort_keys=True)
                else:
                    data_str = str(data)
                checksum_result = self.validator.validate_checksum(data_str, checksum)
                if not checksum_result.is_valid:
                    logger.warning(f"Checksum mismatch from {client_ip}: {checksum_result.message}")

            # Count records
            record_count = 1
            if isinstance(data, list):
                record_count = len(data)
            elif isinstance(data, dict):
                for key in ['events', 'changes', 'records', 'items']:
                    if key in data and isinstance(data[key], list):
                        record_count = len(data[key])
                        break

            # Save to storage
            filepath = self.storage.save_data(
                data=data,
                data_type=data_type,
                source_ip=client_ip,
                host_id=host_id,
                metadata={
                    'agent_version': agent_version,
                    'checksum': checksum,
                    'validation': validation_result.to_dict(),
                }
            )

            # Update statistics
            processing_time = time.time() - start_time
            self.statistics.record_data_received(
                data_size=data_size,
                processing_time=processing_time,
                source_ip=client_ip,
                record_count=record_count,
                success=True
            )

            # Log successful data extraction
            packet_logger.log_data_extracted(
                source_ip=client_ip,
                data_size=data_size,
                data_type=data_type,
                checksum=checksum,
                processing_time=processing_time
            )

            # Store for dashboard
            self._add_received_data({
                'timestamp': datetime.now().isoformat(),
                'source_ip': client_ip,
                'agent_version': agent_version,
                'host_id': host_id,
                'data_type': data_type,
                'data_size': data_size,
                'record_count': record_count,
                'filepath': filepath,
                'validation': validation_result.to_dict(),
            })

            # Broadcast to WebSocket clients
            await self._broadcast_websocket({
                'type': 'data_received',
                'timestamp': datetime.now().isoformat(),
                'source_ip': client_ip,
                'host_id': host_id,
                'data_type': data_type,
                'record_count': record_count,
            })

            # Return success response
            response_data = {
                'status': 'success',
                'message': 'Data received and processed',
                'timestamp': datetime.now().isoformat(),
                'processing_time_ms': round(processing_time * 1000, 2),
                'data_size': data_size,
                'record_count': record_count,
            }

            if not validation_result.is_valid:
                response_data['validation_warnings'] = [validation_result.message]

            return web.json_response(response_data, status=200)

        except Exception as e:
            processing_time = time.time() - start_time
            error_message = f"Failed to process data: {str(e)}"

            logger.error(error_message)

            # Record error
            self.statistics.record_data_received(
                data_size=0,
                processing_time=processing_time,
                source_ip=client_ip,
                success=False
            )
            self.statistics.record_error('data_processing_error')

            packet_logger.log_validation_error(
                source_ip=client_ip,
                error_type='processing_error',
                error_message=str(e),
                data_size=0
            )

            return web.json_response({
                'status': 'error',
                'message': error_message,
                'timestamp': datetime.now().isoformat(),
            }, status=500)

    async def _handle_scout_events(self, request: Request) -> Response:
        """Handle SCOUT Agent event data."""
        return await self._handle_scout_data(request)

    async def _handle_scout_system(self, request: Request) -> Response:
        """Handle SCOUT Agent system data."""
        return await self._handle_scout_data(request)

    # ==================== Health & Status Handlers ====================

    async def _handle_health(self, request: Request) -> Response:
        """Handle health check requests."""
        response = await self.heartbeat.handle_heartbeat_request()
        return web.json_response(response)

    async def _handle_status(self, request: Request) -> Response:
        """Handle detailed status requests."""
        uptime = time.time() - self.start_time if self.start_time else 0

        status_data = {
            'status': 'running' if self.is_running else 'stopped',
            'uptime_seconds': round(uptime, 1),
            'start_time': self.start_time,
            'current_time': time.time(),
            'received_data_count': len(self.received_data),
            'websocket_connections': len(self.websocket_connections),
            'heartbeat_status': self.heartbeat.get_status(),
            'validation_statistics': self.validator.get_validation_statistics(),
            'processing_statistics': self.statistics.get_statistics(),
            'storage_statistics': self.storage.get_storage_stats(),
        }

        return web.json_response(status_data)

    async def _handle_metrics(self, request: Request) -> Response:
        """Handle metrics requests."""
        metrics = self.statistics.get_detailed_metrics()
        return web.json_response(metrics)

    # ==================== Control Handlers ====================

    async def _handle_control_heartbeat(self, request: Request) -> Response:
        """Handle heartbeat control requests."""
        try:
            control_data = await request.json()
            result = await self.heartbeat.update_configuration(control_data)
            return web.json_response({
                'status': 'success',
                'message': 'Heartbeat configuration updated',
                'result': result,
            })
        except Exception as e:
            return web.json_response({
                'status': 'error',
                'message': str(e),
            }, status=400)

    async def _handle_control_simulate(self, request: Request) -> Response:
        """Handle simulation control requests."""
        try:
            data = await request.json()
            scenario = data.get('scenario', 'normal')
            duration = data.get('duration', 60)

            result = await self.heartbeat.simulate_scenario(scenario, duration)

            return web.json_response({
                'status': 'success' if result.get('success') else 'error',
                'message': f"Scenario '{scenario}' activated" if result.get('success') else result.get('error'),
                'result': result,
            })
        except Exception as e:
            return web.json_response({
                'status': 'error',
                'message': str(e),
            }, status=400)

    async def _handle_control_stats(self, request: Request) -> Response:
        """Handle statistics requests."""
        stats = {
            'server_statistics': self.statistics.get_statistics(),
            'validation_statistics': self.validator.get_validation_statistics(),
            'heartbeat_statistics': self.heartbeat.get_statistics(),
            'storage_statistics': self.storage.get_storage_stats(),
            'data_summary': {
                'total_received': len(self.received_data),
                'recent_data': self.received_data[-10:],
            },
        }
        return web.json_response(stats)

    async def _handle_control_reset(self, request: Request) -> Response:
        """Handle reset requests."""
        try:
            self.statistics.reset_statistics()
            self.validator.reset_statistics()
            self.heartbeat.reset_statistics()
            self.received_data.clear()

            logger.info("Server statistics and data reset")

            return web.json_response({
                'status': 'success',
                'message': 'Server statistics and data reset successfully',
            })
        except Exception as e:
            return web.json_response({
                'status': 'error',
                'message': str(e),
            }, status=500)

    # ==================== Web Interface Handlers ====================

    async def _handle_dashboard(self, request: Request) -> Response:
        """Serve the monitoring dashboard."""
        html = self._generate_dashboard_html()
        return web.Response(text=html, content_type='text/html')

    async def _handle_api_data(self, request: Request) -> Response:
        """Return recent received data."""
        limit = int(request.query.get('limit', 20))
        data = self.received_data[-limit:] if self.received_data else []
        return web.json_response(list(reversed(data)))

    async def _handle_api_statistics(self, request: Request) -> Response:
        """Return statistics for dashboard."""
        return web.json_response(self.statistics.get_statistics())

    async def _handle_api_storage(self, request: Request) -> Response:
        """Return storage statistics."""
        return web.json_response(self.storage.get_storage_stats())

    async def _handle_websocket(self, request: Request) -> Response:
        """Handle WebSocket connections for real-time updates."""
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        self.websocket_connections.add(ws)
        logger.info(f"WebSocket connection from {request.remote}")

        try:
            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                        await ws.send_str(json.dumps({
                            'type': 'response',
                            'message': 'Command received',
                        }))
                    except json.JSONDecodeError:
                        await ws.send_str(json.dumps({
                            'type': 'error',
                            'message': 'Invalid JSON',
                        }))
                elif msg.type == WSMsgType.ERROR:
                    logger.error(f'WebSocket error: {ws.exception()}')
                    break
        except Exception as e:
            logger.error(f"WebSocket error: {e}")
        finally:
            self.websocket_connections.discard(ws)
            logger.info(f"WebSocket closed from {request.remote}")

        return ws

    # ==================== Helper Methods ====================

    def _add_received_data(self, entry: Dict[str, Any]) -> None:
        """Add entry to received data list."""
        self.received_data.append(entry)
        if len(self.received_data) > self.max_received_data:
            self.received_data = self.received_data[-self.max_received_data:]

    async def _broadcast_websocket(self, message: Dict[str, Any]) -> None:
        """Broadcast message to all WebSocket clients."""
        if not self.websocket_connections:
            return

        message_str = json.dumps(message)
        disconnected = set()

        for ws in self.websocket_connections:
            try:
                await ws.send_str(message_str)
            except Exception:
                disconnected.add(ws)

        self.websocket_connections -= disconnected

    def _generate_dashboard_html(self) -> str:
        """Generate the monitoring dashboard HTML."""
        return '''<!DOCTYPE html>
<html>
<head>
    <title>Scout Receiver Dashboard</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
               background: #1a1a2e; color: #eee; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #00d4ff; margin-bottom: 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .card { background: #16213e; border-radius: 8px; padding: 20px; }
        .card h2 { color: #00d4ff; font-size: 1.1em; margin-bottom: 15px; border-bottom: 1px solid #0f3460; padding-bottom: 10px; }
        .stat { display: flex; justify-content: space-between; margin: 8px 0; }
        .stat-label { color: #888; }
        .stat-value { color: #00d4ff; font-weight: bold; }
        .data-entry { background: #0f3460; padding: 10px; margin: 5px 0; border-radius: 4px; font-size: 0.9em; }
        .data-entry.success { border-left: 3px solid #00ff88; }
        .data-entry.error { border-left: 3px solid #ff4444; }
        .refresh-btn { background: #00d4ff; color: #1a1a2e; border: none; padding: 10px 20px;
                      border-radius: 4px; cursor: pointer; font-weight: bold; }
        .refresh-btn:hover { background: #00a8cc; }
        .status-badge { display: inline-block; padding: 3px 8px; border-radius: 3px; font-size: 0.8em; }
        .status-badge.healthy { background: #00ff88; color: #000; }
        .status-badge.running { background: #00d4ff; color: #000; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #0f3460; }
        th { color: #888; font-weight: normal; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Scout Receiver Dashboard</h1>
        <button class="refresh-btn" onclick="refreshData()">Refresh</button>

        <div class="grid" style="margin-top: 20px;">
            <div class="card">
                <h2>Server Status</h2>
                <div class="stat"><span class="stat-label">Status</span><span id="status" class="status-badge">Loading...</span></div>
                <div class="stat"><span class="stat-label">Uptime</span><span id="uptime" class="stat-value">-</span></div>
                <div class="stat"><span class="stat-label">Total Requests</span><span id="total-requests" class="stat-value">-</span></div>
                <div class="stat"><span class="stat-label">Success Rate</span><span id="success-rate" class="stat-value">-</span></div>
            </div>

            <div class="card">
                <h2>Data Statistics</h2>
                <div class="stat"><span class="stat-label">Data Received</span><span id="data-received" class="stat-value">-</span></div>
                <div class="stat"><span class="stat-label">Records Processed</span><span id="records" class="stat-value">-</span></div>
                <div class="stat"><span class="stat-label">Unique Sources</span><span id="sources" class="stat-value">-</span></div>
                <div class="stat"><span class="stat-label">Avg Processing</span><span id="avg-time" class="stat-value">-</span></div>
            </div>

            <div class="card">
                <h2>Storage</h2>
                <div class="stat"><span class="stat-label">Files Created</span><span id="files-created" class="stat-value">-</span></div>
                <div class="stat"><span class="stat-label">Total Size</span><span id="storage-size" class="stat-value">-</span></div>
                <div class="stat"><span class="stat-label">Disk Free</span><span id="disk-free" class="stat-value">-</span></div>
            </div>
        </div>

        <div class="card" style="margin-top: 20px;">
            <h2>Recent Data</h2>
            <div id="recent-data">Loading...</div>
        </div>
    </div>

    <script>
        async function refreshData() {
            try {
                const [statsRes, dataRes, storageRes] = await Promise.all([
                    fetch('/api/statistics'),
                    fetch('/api/data?limit=10'),
                    fetch('/api/storage')
                ]);

                const stats = await statsRes.json();
                const data = await dataRes.json();
                const storage = await storageRes.json();

                document.getElementById('status').textContent = 'Running';
                document.getElementById('status').className = 'status-badge running';
                document.getElementById('uptime').textContent = Math.round(stats.uptime_seconds) + 's';
                document.getElementById('total-requests').textContent = stats.total_requests;
                document.getElementById('success-rate').textContent = stats.success_rate + '%';
                document.getElementById('data-received').textContent = stats.total_data_received_mb + ' MB';
                document.getElementById('records').textContent = stats.total_records_received;
                document.getElementById('sources').textContent = stats.unique_sources;
                document.getElementById('avg-time').textContent = (stats.average_processing_time * 1000).toFixed(1) + 'ms';

                document.getElementById('files-created').textContent = storage.files_created || storage.total_files || 0;
                document.getElementById('storage-size').textContent = (storage.total_size_mb || 0) + ' MB';
                document.getElementById('disk-free').textContent = (storage.disk_free_pct || 'N/A') + '%';

                const dataHtml = data.map(entry => `
                    <div class="data-entry success">
                        <strong>${entry.timestamp}</strong> - ${entry.source_ip} (${entry.data_type})<br>
                        Host: ${entry.host_id} | Records: ${entry.record_count} | Size: ${entry.data_size} bytes
                    </div>
                `).join('') || '<p>No data received yet</p>';

                document.getElementById('recent-data').innerHTML = dataHtml;

            } catch (error) {
                console.error('Refresh failed:', error);
            }
        }

        setInterval(refreshData, 5000);
        refreshData();
    </script>
</body>
</html>'''

    # ==================== Server Lifecycle ====================

    async def start(self, host: Optional[str] = None,
                   port: Optional[int] = None) -> None:
        """Start the HTTP server.

        Args:
            host: Host address to bind to
            port: Port number to bind to
        """
        host = host or self.config.get('server.host', '0.0.0.0')
        port = port or self.config.get('server.port', 8080)

        self.is_running = True
        self.start_time = time.time()

        # Start heartbeat handler
        await self.heartbeat.start()

        logger.info(f"Starting Scout Receiver on {host}:{port}")

        # Create and start the web server
        runner = web.AppRunner(self.app)
        await runner.setup()

        site = web.TCPSite(runner, host, port)
        await site.start()

        logger.info(f"Scout Receiver started successfully on http://{host}:{port}")

    async def stop(self) -> None:
        """Stop the HTTP server."""
        self.is_running = False

        # Stop heartbeat
        await self.heartbeat.stop()

        # Close WebSocket connections
        for ws in self.websocket_connections.copy():
            await ws.close()

        logger.info("Scout Receiver stopped")

    def get_statistics(self) -> Dict[str, Any]:
        """Get server statistics."""
        return {
            'is_running': self.is_running,
            'start_time': self.start_time,
            'uptime': time.time() - self.start_time if self.start_time else 0,
            'received_data_count': len(self.received_data),
            'websocket_connections': len(self.websocket_connections),
            'processing_statistics': self.statistics.get_statistics(),
            'validation_statistics': self.validator.get_validation_statistics(),
            'heartbeat_statistics': self.heartbeat.get_statistics(),
            'storage_statistics': self.storage.get_storage_stats(),
        }


async def main() -> None:
    """Main entry point for the server."""
    # Load configuration
    config = load_config()

    # Setup logging
    logging_config = config.get_section('logging')
    setup_logging(
        level=logging_config.get('level', 'INFO'),
        format_type=logging_config.get('format', 'structured'),
        log_file=logging_config.get('file'),
        max_size_mb=logging_config.get('max_size_mb', 50),
        backup_count=logging_config.get('backup_count', 5),
    )

    # Check if enabled
    if not config.is_enabled():
        logger.info("Scout Receiver is disabled in configuration")
        return

    # Create and start server
    server = ScoutReceiverServer(config)

    server_config = config.get_section('server')
    host = server_config.get('host', '0.0.0.0')
    port = server_config.get('port', 8080)

    try:
        await server.start(host, port)

        # Keep server running
        while True:
            await asyncio.sleep(1)

    except KeyboardInterrupt:
        logger.info("Received shutdown signal")
    finally:
        await server.stop()


if __name__ == '__main__':
    asyncio.run(main())
