import {Component, Input, OnInit} from '@angular/core';
import {ActivatedRoute, Router} from '@angular/router';
import {Ticket} from '../../models/ticket.model';
import {SearchService} from '../../services/search.service';

@Component({
    selector: 'app-ticket-detail',
    standalone: false,
    templateUrl: './ticket-detail.component.html',
    styleUrl: './ticket-detail.component.css'
})
export class TicketDetailComponent implements OnInit {
    @Input() ticketId?: number;
    ticket?: Ticket;
    isLoading = true;
    error = '';

    constructor(
        private route: ActivatedRoute,
        private router: Router,
        private searchService: SearchService
    ) {
    }

    ngOnInit(): void {
        // If ticketId is passed as @Input, use it directly
        if (this.ticketId) {
            this.loadTicket(this.ticketId);
        } else {
            // Otherwise, get it from the route params
            this.route.params.subscribe(params => {
                const id = Number(params['id']);
                if (id) {
                    this.loadTicket(id);
                } else {
                    this.error = 'No ticket ID provided';
                    this.isLoading = false;
                }
            });
        }
    }

    loadTicket(id: number): void {
        this.isLoading = true;
        this.searchService.getTicketById(id).subscribe({
            next: (ticket) => {
                this.ticket = ticket;
                this.isLoading = false;
                console.log('Ticket loaded:', this.ticket);
            },
            error: (err) => {
                console.error('Error loading ticket:', err);
                this.error = 'Failed to load ticket details';
                this.isLoading = false;
            }
        });
    }

    getKeywordText(keyword: string | { word: string }): string {
        if (typeof keyword === 'string') {
            return keyword;
        } else if (keyword && keyword.word) {
            return keyword.word;
        }
        return '';
    }

    getKeyPointText(keyPoint: string | { point: string }): string {
        if (typeof keyPoint === 'string') {
            return keyPoint;
        } else if (keyPoint && keyPoint.point) {
            return keyPoint.point;
        }
        return '';
    }

    goBack(): void {
        this.router.navigate(['/search']);
    }

    // New method to navigate back with search term
    navigateToSearch(searchTerm: string): void {
        // Store the search term in the service so SearchComponent can use it
        this.searchService.setSearchTerm(searchTerm);

        // Also store it in localStorage as a backup mechanism
        localStorage.setItem('pendingSearchTerm', searchTerm);

        this.router.navigate(['/search']);
    }

    // New method to handle keyword click
    onKeywordClick(keyword: string | { word: string }): void {
        const text = this.getKeywordText(keyword);
        this.navigateToSearch(text);
    }

    // New method to handle key point click
    onKeyPointClick(keyPoint: string | { point: string }): void {
        const text = this.getKeyPointText(keyPoint);
        this.navigateToSearch(text);
    }

    // New method to handle meta tag click
    onMetaTagClick(tagText: string): void {
        this.navigateToSearch(tagText);
    }
}
