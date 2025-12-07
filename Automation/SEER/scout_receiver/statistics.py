"""
Statistics Collection for Scout Receiver

Tracks and reports metrics for data reception, processing,
and server performance.
"""

import time
from collections import defaultdict
from datetime import datetime
from threading import Lock
from typing import Any, Dict, List, Optional

from .utils.logging import get_logger

logger = get_logger(__name__)


class StatisticsCollector:
    """Collects and manages server statistics and metrics."""

    def __init__(self):
        """Initialize statistics collector."""
        self._lock = Lock()

        # Request statistics
        self.total_requests = 0
        self.successful_requests = 0
        self.failed_requests = 0

        # Data statistics
        self.total_data_received = 0  # bytes
        self.total_records_received = 0

        # Timing statistics
        self.total_processing_time = 0.0
        self.min_processing_time = float('inf')
        self.max_processing_time = 0.0

        # Per-source statistics
        self.source_stats: Dict[str, Dict[str, Any]] = defaultdict(lambda: {
            'requests': 0,
            'bytes': 0,
            'records': 0,
            'last_seen': None,
            'errors': 0,
        })

        # Error tracking
        self.error_counts: Dict[str, int] = defaultdict(int)

        # Recent requests (for dashboard)
        self.recent_requests: List[Dict[str, Any]] = []
        self.max_recent_requests = 100

        # Start time
        self.start_time = time.time()

    def record_data_received(self, data_size: int,
                            processing_time: float,
                            source_ip: str,
                            record_count: int = 1,
                            success: bool = True) -> None:
        """Record a data reception event.

        Args:
            data_size: Size of received data in bytes
            processing_time: Time taken to process in seconds
            source_ip: Source IP address
            record_count: Number of records in the data
            success: Whether processing was successful
        """
        with self._lock:
            self.total_requests += 1

            if success:
                self.successful_requests += 1
                self.total_data_received += data_size
                self.total_records_received += record_count
                self.total_processing_time += processing_time

                # Update min/max processing times
                if processing_time < self.min_processing_time:
                    self.min_processing_time = processing_time
                if processing_time > self.max_processing_time:
                    self.max_processing_time = processing_time
            else:
                self.failed_requests += 1

            # Update per-source stats
            src_stats = self.source_stats[source_ip]
            src_stats['requests'] += 1
            src_stats['bytes'] += data_size
            src_stats['records'] += record_count
            src_stats['last_seen'] = datetime.now().isoformat()
            if not success:
                src_stats['errors'] += 1

            # Add to recent requests
            self.recent_requests.append({
                'timestamp': datetime.now().isoformat(),
                'source_ip': source_ip,
                'data_size': data_size,
                'record_count': record_count,
                'processing_time_ms': round(processing_time * 1000, 2),
                'success': success,
            })

            # Trim recent requests list
            if len(self.recent_requests) > self.max_recent_requests:
                self.recent_requests = self.recent_requests[-self.max_recent_requests:]

    def record_error(self, error_type: str) -> None:
        """Record an error occurrence.

        Args:
            error_type: Type/category of the error
        """
        with self._lock:
            self.error_counts[error_type] += 1

    def get_statistics(self) -> Dict[str, Any]:
        """Get current statistics summary.

        Returns:
            Dictionary containing current statistics
        """
        with self._lock:
            uptime = time.time() - self.start_time

            avg_processing_time = 0.0
            if self.successful_requests > 0:
                avg_processing_time = (
                    self.total_processing_time / self.successful_requests
                )

            success_rate = 0.0
            if self.total_requests > 0:
                success_rate = self.successful_requests / self.total_requests

            return {
                'uptime_seconds': round(uptime, 1),
                'total_requests': self.total_requests,
                'successful_requests': self.successful_requests,
                'failed_requests': self.failed_requests,
                'success_rate': round(success_rate * 100, 2),
                'total_data_received': self.total_data_received,
                'total_data_received_mb': round(
                    self.total_data_received / (1024 * 1024), 2
                ),
                'total_records_received': self.total_records_received,
                'average_processing_time': round(avg_processing_time, 4),
                'min_processing_time': (
                    round(self.min_processing_time, 4)
                    if self.min_processing_time != float('inf') else 0
                ),
                'max_processing_time': round(self.max_processing_time, 4),
                'unique_sources': len(self.source_stats),
                'requests_per_minute': self._calculate_rpm(),
            }

    def get_detailed_metrics(self) -> Dict[str, Any]:
        """Get detailed performance metrics.

        Returns:
            Dictionary containing detailed metrics
        """
        with self._lock:
            basic_stats = self.get_statistics()

            # Add per-source breakdown
            source_breakdown = []
            for ip, stats in sorted(
                self.source_stats.items(),
                key=lambda x: x[1]['requests'],
                reverse=True
            ):
                source_breakdown.append({
                    'source_ip': ip,
                    **stats
                })

            # Add error breakdown
            error_breakdown = dict(self.error_counts)

            return {
                **basic_stats,
                'source_breakdown': source_breakdown[:20],  # Top 20 sources
                'error_breakdown': error_breakdown,
                'recent_requests': self.recent_requests[-10:],
            }

    def get_recent_activity(self, limit: int = 20) -> List[Dict[str, Any]]:
        """Get recent request activity.

        Args:
            limit: Maximum number of entries to return

        Returns:
            List of recent request records
        """
        with self._lock:
            return list(reversed(self.recent_requests[-limit:]))

    def get_source_statistics(self, source_ip: str) -> Optional[Dict[str, Any]]:
        """Get statistics for a specific source.

        Args:
            source_ip: Source IP address

        Returns:
            Source statistics or None if not found
        """
        with self._lock:
            if source_ip in self.source_stats:
                return {
                    'source_ip': source_ip,
                    **self.source_stats[source_ip]
                }
            return None

    def _calculate_rpm(self) -> float:
        """Calculate requests per minute rate.

        Returns:
            Requests per minute
        """
        uptime_minutes = (time.time() - self.start_time) / 60
        if uptime_minutes < 0.1:  # Less than 6 seconds
            return 0.0
        return round(self.total_requests / uptime_minutes, 2)

    def reset_statistics(self) -> None:
        """Reset all statistics to initial state."""
        with self._lock:
            self.total_requests = 0
            self.successful_requests = 0
            self.failed_requests = 0
            self.total_data_received = 0
            self.total_records_received = 0
            self.total_processing_time = 0.0
            self.min_processing_time = float('inf')
            self.max_processing_time = 0.0
            self.source_stats.clear()
            self.error_counts.clear()
            self.recent_requests.clear()
            self.start_time = time.time()

            logger.info("Statistics reset")

    def get_health_summary(self) -> Dict[str, Any]:
        """Get a health summary for monitoring.

        Returns:
            Health status dictionary
        """
        stats = self.get_statistics()

        # Determine health status
        if stats['total_requests'] == 0:
            status = 'idle'
        elif stats['success_rate'] >= 99:
            status = 'healthy'
        elif stats['success_rate'] >= 95:
            status = 'degraded'
        else:
            status = 'unhealthy'

        return {
            'status': status,
            'uptime_seconds': stats['uptime_seconds'],
            'total_requests': stats['total_requests'],
            'success_rate': stats['success_rate'],
            'unique_sources': stats['unique_sources'],
            'last_activity': (
                self.recent_requests[-1]['timestamp']
                if self.recent_requests else None
            ),
        }
